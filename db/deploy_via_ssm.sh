#!/usr/bin/env bash
# Run a JobPush db script on EC2 via SSM (RDS is VPC-private).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <script-relative-to-repo> [extra paths to include...]" >&2
  echo "Example: $0 db/run_migration_019.sh" >&2
  exit 2
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${REGION:-us-east-2}"
EC2_INSTANCE="${EC2_INSTANCE:-i-0bdee6f611283586f}"
RUN_SCRIPT="$1"
shift

DB_REF_PATTERN='(migrations|analysis|refresh|load|repair|ops)/[A-Za-z0-9_./-]+\.(sql|sh|csv)'
RUN_REF_PATTERN='run_[A-Za-z0-9_.-]+\.sh'

extract_matches() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -o "$pattern" "$file"
  else
    grep -Eho "$pattern" "$file" || true
  fi
}

STAGING="$(mktemp -d -t jobpush-ssm-deploy.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/db/lib" "$STAGING/db/migrations" "$STAGING/db/refresh"
if [[ -d "$REPO_DIR/scripts" ]]; then
  mkdir -p "$STAGING/scripts"
  for script in \
    crawl_apple_jobs.py crawl_greenhouse.py crawl_icims.py \
    crawl_oracle_cloud.py crawl_workday.py crawl_lever.py crawl_ashby.py crawl_jobvite.py crawl_paylocity.py crawl_rippling.py \
    crawl_smartrecruiters.py crawl_workable.py discover_career_sites.py \
    resolve_generic_ats_links.py \
    classify_job_titles_ai.py \
    train_local_title_classifier.py market_scope.py; do
    [[ -f "$REPO_DIR/scripts/$script" ]] && cp "$REPO_DIR/scripts/$script" "$STAGING/scripts/$script"
  done
fi

cp -R "$REPO_DIR/db/lib/." "$STAGING/db/lib/"

# SSM RunCommand has a small document payload limit. Include only SQL/shell
# assets explicitly referenced by the selected runner instead of copying every
# historical migration and analysis file on every deployment.
while IFS= read -r referenced; do
  [[ -n "$referenced" && -f "$REPO_DIR/db/$referenced" ]] || continue
  mkdir -p "$STAGING/db/$(dirname "$referenced")"
  cp "$REPO_DIR/db/$referenced" "$STAGING/db/$referenced"
done < <(extract_matches "$DB_REF_PATTERN" "$REPO_DIR/$RUN_SCRIPT" | sort -u)

# Wrapper runners often call another script in db/ through $SCRIPT_DIR. Those
# references have no directory prefix, so include matching root-level runners.
while IFS= read -r referenced; do
  [[ -n "$referenced" && -f "$REPO_DIR/db/$referenced" ]] || continue
  cp "$REPO_DIR/db/$referenced" "$STAGING/db/$referenced"
  chmod +x "$STAGING/db/$referenced"
  while IFS= read -r nested; do
    [[ -n "$nested" && -f "$REPO_DIR/db/$nested" ]] || continue
    mkdir -p "$STAGING/db/$(dirname "$nested")"
    cp "$REPO_DIR/db/$nested" "$STAGING/db/$nested"
  done < <(extract_matches "$DB_REF_PATTERN" "$REPO_DIR/db/$referenced" | sort -u)
done < <(extract_matches "$RUN_REF_PATTERN" "$REPO_DIR/$RUN_SCRIPT" | sort -u)

for extra in "$@"; do
  dest="$STAGING/$extra"
  mkdir -p "$(dirname "$dest")"
  cp -R "$REPO_DIR/$extra" "$dest"
done

cp "$REPO_DIR/$RUN_SCRIPT" "$STAGING/$RUN_SCRIPT"
chmod +x "$STAGING/$RUN_SCRIPT" "$STAGING/db/lib/connect_rds.sh"

ARCHIVE="$(mktemp -t jobpush-ssm.XXXXXX.tgz)"
COPYFILE_DISABLE=1 tar --exclude='__pycache__' --exclude='*.pyc' -czf "$ARCHIVE" -C "$STAGING" .
PAYLOAD=$(base64 < "$ARCHIVE" | tr -d '\n')
REMOTE_DIR="/tmp/jobpush-ssm-$$"

COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$EC2_INSTANCE" \
  --document-name AWS-RunShellScript \
  --parameters commands="[
\"set -euo pipefail\",
\"rm -rf $REMOTE_DIR\",
\"mkdir -p $REMOTE_DIR\",
\"echo $PAYLOAD | base64 -d | tar xzf - -C $REMOTE_DIR\",
\"chmod +x $REMOTE_DIR/$RUN_SCRIPT $REMOTE_DIR/db/lib/connect_rds.sh\",
\"cd $REMOTE_DIR && bash $RUN_SCRIPT\",
\"rm -rf $REMOTE_DIR\"
]" \
  --query 'Command.CommandId' \
  --output text)

echo "SSM CommandId: $COMMAND_ID"
echo "Polling EC2 $EC2_INSTANCE ..."

for _ in $(seq 1 360); do
  sleep 10
  STATUS=$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$EC2_INSTANCE" \
    --query Status \
    --output text 2>/dev/null || echo Pending)

  if [[ "$STATUS" == "Success" ]]; then
    aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$COMMAND_ID" \
      --instance-id "$EC2_INSTANCE" \
      --query '{Stdout:StandardOutputContent,Stderr:StandardErrorContent}' \
      --output json
    exit 0
  fi

  if [[ "$STATUS" == "Failed" || "$STATUS" == "Cancelled" || "$STATUS" == "TimedOut" ]]; then
    aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$COMMAND_ID" \
      --instance-id "$EC2_INSTANCE" \
      --output json
    exit 1
  fi
done

echo "Timed out waiting for SSM command" >&2
exit 1
