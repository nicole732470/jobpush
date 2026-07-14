#!/usr/bin/env bash
# After the nightly crawl and title classification finish, email today's new target jobs as JSON.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

EXPORT_DATE="${1:-$(TZ=America/Chicago date +%F)}"
EXPORT_DIR="${JOBPUSH_DAILY_EXPORT_DIR:-$REPO_DIR/daily_exports}"
EMAIL_TO="${JOBPUSH_EXPORT_EMAIL:-nicole732470@gmail.com,yuli2026@u.northwestern.edu}"
EMAIL_FROM="${JOBPUSH_EXPORT_FROM_EMAIL:-nicole732470@gmail.com}"
MAX_ATTACHMENT_BYTES="${JOBPUSH_MAX_EMAIL_ATTACHMENT_BYTES:-24000000}"
WORK_DIR="$(mktemp -d -t jobpush-daily-export.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

[[ "$EXPORT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "export date must be YYYY-MM-DD" >&2; exit 2; }
mkdir -p "$EXPORT_DIR"

if [[ "${JOBPUSH_CRAWL_COMPLETE:-0}" != "1" ]]; then
  REMAINING_DUE="$("${PSQL[@]}" -qAt -c "SELECT count(*) FROM jobpush.crawl_schedule_queue WHERE is_due AND crawl_status <> 'running';")"
  if (( REMAINING_DUE > 0 )); then
    echo "Daily export withheld: $REMAINING_DUE due sites remain after the crawl." >&2
    exit 1
  fi
fi

JSON_LINES="$WORK_DIR/jobs.jsonl"
EXPORT_JSON="$EXPORT_DIR/$EXPORT_DATE.json"
REPORT_JSON="$EXPORT_DIR/$EXPORT_DATE.report.json"
SES_REQUEST="$WORK_DIR/ses_request.json"

"${PSQL[@]}" -qAt -v ON_ERROR_STOP=1 -c "
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'company', target.canonical_name,
    'title', posting.title,
    'location', NULLIF(posting.location,''),
    'category', NULLIF(posting.category,''),
    'employment_type', NULLIF(posting.employment_type,''),
    'description', NULLIF(posting.description_snippet,''),
    'posted_date', NULLIF(posting.posted_text,''),
    'first_seen_at', posting.first_seen_at,
    'job_url', posting.job_url,
    'role_family', label.canonical_role,
    'company_tier', target.priority_tier
  ))::text
  FROM jobpush.job_postings_us posting
  JOIN jobpush.crawl_targets target USING(consolidation_key)
  JOIN jobpush.job_title_labels label USING(normalized_title)
  WHERE posting.active
    AND label.classification_status='target'
    AND (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date='$EXPORT_DATE'::date
  ORDER BY posting.first_seen_at DESC, target.canonical_name, posting.title
" > "$JSON_LINES"

jq -s . "$JSON_LINES" > "$EXPORT_JSON"
EXPORTED="$(jq length "$EXPORT_JSON")"
jq -n --arg date "$EXPORT_DATE" --argjson exported "$EXPORTED" \
  '{export_date:$date, scope:"new_target_jobs_only", exported_jobs:$exported}' > "$REPORT_JSON"

EMAIL_STATUS="pending"
EMAIL_ERROR=""
FILE_SIZE="$(stat -c %s "$EXPORT_JSON" 2>/dev/null || stat -f %z "$EXPORT_JSON")"
if (( FILE_SIZE > MAX_ATTACHMENT_BYTES )); then
  EMAIL_STATUS="failed"
  EMAIL_ERROR="attachment_too_large: ${FILE_SIZE} bytes exceeds ${MAX_ATTACHMENT_BYTES}"
else
  python3 "$REPO_DIR/scripts/build_ses_attachment_request.py" \
    "$EXPORT_JSON" "$REPORT_JSON" "$SES_REQUEST" \
    --sender "$EMAIL_FROM" --recipients "$EMAIL_TO" --date "$EXPORT_DATE"
  if aws sesv2 send-email --region us-east-2 --cli-input-json "file://$SES_REQUEST" >/dev/null 2>"$WORK_DIR/email_error"; then
    EMAIL_STATUS="sent"
  else
    EMAIL_STATUS="failed"
    EMAIL_ERROR="$(tail -c 1000 "$WORK_DIR/email_error")"
  fi
fi

"${PSQL[@]}" -v ON_ERROR_STOP=1 -v export_date="$EXPORT_DATE" -v export_path="$EXPORT_JSON" \
  -v exported="$EXPORTED" -v email_status="$EMAIL_STATUS" -v email_error="$EMAIL_ERROR" <<'SQL'
INSERT INTO jobpush.daily_job_exports(
  export_date,status,export_path,jobs_discovered,jobs_processed,successful_jd_retrieval,
  skipped_jobs,failed_jobs,exported_jobs,report,email_status,email_error,started_at,finished_at
) VALUES (
  :'export_date','succeeded',:'export_path',:exported,:exported,0,0,0,:exported,
  jsonb_build_object('scope','new_target_jobs_only','exported_jobs',:exported),
  :'email_status',NULLIF(:'email_error',''),now(),now()
)
ON CONFLICT(export_date) DO UPDATE SET
  status='succeeded',export_path=EXCLUDED.export_path,jobs_discovered=EXCLUDED.jobs_discovered,
  jobs_processed=EXCLUDED.jobs_processed,successful_jd_retrieval=0,skipped_jobs=0,failed_jobs=0,
  exported_jobs=EXCLUDED.exported_jobs,report=EXCLUDED.report,email_status=EXCLUDED.email_status,
  email_error=EXCLUDED.email_error,started_at=now(),finished_at=now();
SQL

echo "Daily target export complete: date=$EXPORT_DATE jobs=$EXPORTED email=$EMAIL_STATUS"
