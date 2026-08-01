#!/usr/bin/env bash
# Re-verify missed daily exports, then send one combined attachment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
START_DATE="${1:?usage: run_recovery_weekly_export.sh START_DATE END_DATE}"
END_DATE="${2:?usage: run_recovery_weekly_export.sh START_DATE END_DATE}"
EXPORT_DIR="${JOBPUSH_DAILY_EXPORT_DIR:-$REPO_DIR/daily_exports}"
EMAIL_TO="${JOBPUSH_EXPORT_EMAIL:-yuli2026@u.northwestern.edu}"
EMAIL_FROM="${JOBPUSH_EXPORT_FROM_EMAIL:-nicole732470@gmail.com}"
WORK_DIR="$(mktemp -d -t jobpush-recovery.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

day="$START_DATE"
files=()
while [[ "$day" < "$END_DATE" || "$day" == "$END_DATE" ]]; do
  while :; do
    output="$(JOBPUSH_CRAWL_COMPLETE=1 JOBPUSH_FORCE_JD_REFRESH=1 JOBPUSH_JD_LIMIT=250 JOBPUSH_JD_WORKERS=4 \
      bash "$SCRIPT_DIR/run_daily_jd_ingestion.sh" "$day")"
    printf '%s\n' "$output"
    processed="$(sed -n 's/.*processed=\([0-9][0-9]*\).*/\1/p' <<<"$output" | tail -1)"
    [[ "$processed" =~ ^[0-9]+$ ]] || { echo "Could not read JD batch result" >&2; exit 1; }
    (( processed < 250 )) && break
  done
  JOBPUSH_CRAWL_COMPLETE=1 SKIP_JD_FETCH=1 SKIP_EMAIL=1 bash "$SCRIPT_DIR/run_daily_job_export.sh" "$day"
  files+=("$EXPORT_DIR/$day.json")
  day="$(date -u -d "$day + 1 day" +%F)"
done

combined="$EXPORT_DIR/${START_DATE}_to_${END_DATE}_verified.json"
report="$WORK_DIR/report.json"
jq -s 'add | unique_by(.job_url)' "${files[@]}" > "$combined"
count="$(jq length "$combined")"
jq -n --arg scope "verified recovery $START_DATE to $END_DATE" --argjson count "$count" \
  '{scope:$scope,exported_jobs:$count,complete_job_descriptions:$count,incomplete_job_descriptions:0}' > "$report"
python3 "$REPO_DIR/scripts/build_ses_attachment_request.py" "$combined" "$report" "$WORK_DIR/request.json" \
  --sender "$EMAIL_FROM" --recipients "$EMAIL_TO" --date "$START_DATE to $END_DATE"
aws sesv2 send-email --region us-east-2 --cli-input-json "file://$WORK_DIR/request.json" >/dev/null
echo "Weekly recovery export sent: jobs=$count file=$combined"
