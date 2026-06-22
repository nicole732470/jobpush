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

STAGING="$(mktemp -d -t jobpush-ssm-deploy.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/db/lib" "$STAGING/db/migrations" "$STAGING/db/refresh"
[[ -d "$REPO_DIR/db/analysis" ]] && mkdir -p "$STAGING/db/analysis" && cp -R "$REPO_DIR/db/analysis/." "$STAGING/db/analysis/"
[[ -d "$REPO_DIR/db/load" ]] && mkdir -p "$STAGING/db/load" && cp -R "$REPO_DIR/db/load/." "$STAGING/db/load/"
[[ -d "$REPO_DIR/scripts" ]] && mkdir -p "$STAGING/scripts" && cp -R "$REPO_DIR/scripts/." "$STAGING/scripts/"

cp "$REPO_DIR/db/lib/connect_rds.sh" "$STAGING/db/lib/"
cp -R "$REPO_DIR/db/migrations/." "$STAGING/db/migrations/"
cp -R "$REPO_DIR/db/refresh/." "$STAGING/db/refresh/"

for extra in "$@"; do
  dest="$STAGING/$extra"
  mkdir -p "$(dirname "$dest")"
  cp -R "$REPO_DIR/$extra" "$dest"
done

cp "$REPO_DIR/$RUN_SCRIPT" "$STAGING/$RUN_SCRIPT"
chmod +x "$STAGING/$RUN_SCRIPT" "$STAGING/db/lib/connect_rds.sh"

ARCHIVE="$(mktemp -t jobpush-ssm.XXXXXX.tgz)"
tar czf "$ARCHIVE" -C "$STAGING" .
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
