#!/usr/bin/env bash
# After the nightly crawl and title classification finish, email today's new target jobs as JSON.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

EXPORT_DATE="${1:-$(TZ=America/Chicago date +%F)}"
EXPORT_DIR="${JOBPUSH_DAILY_EXPORT_DIR:-$REPO_DIR/daily_exports}"
EMAIL_TO="${JOBPUSH_EXPORT_EMAIL:-yuli2026@u.northwestern.edu}"
EMAIL_FROM="${JOBPUSH_EXPORT_FROM_EMAIL:-nicole732470@gmail.com}"
EXPORT_SCOPE="${JOBPUSH_EXPORT_SCOPE:-new_target_jobs_only}"
MAX_ATTACHMENT_BYTES="${JOBPUSH_MAX_EMAIL_ATTACHMENT_BYTES:-24000000}"
WORKERS="${JOBPUSH_JD_WORKERS:-8}"
JD_LIMIT="${JOBPUSH_JD_LIMIT:-0}"
SKIP_EMAIL="${JOBPUSH_SKIP_EMAIL:-0}"
SKIP_EXPORT="${JOBPUSH_SKIP_EXPORT:-0}"
JD_INPUT_FILE="${JOBPUSH_JD_INPUT_FILE:-}"
SKIP_JD_FETCH="${JOBPUSH_SKIP_JD_FETCH:-0}"
JD_PARSER_VERSION="${JOBPUSH_JD_PARSER_VERSION:-jd-v2-complete-content}"
WORK_DIR="$(mktemp -d -t jobpush-daily-export.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

[[ "$EXPORT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "export date must be YYYY-MM-DD" >&2; exit 2; }
[[ "$EXPORT_SCOPE" == "new_target_jobs_only" || "$EXPORT_SCOPE" == "all_active_target" ]] || { echo "invalid JOBPUSH_EXPORT_SCOPE" >&2; exit 2; }
[[ "$JD_LIMIT" =~ ^[0-9]+$ ]] || { echo "JOBPUSH_JD_LIMIT must be a non-negative integer" >&2; exit 2; }
mkdir -p "$EXPORT_DIR"

DATE_FILTER="AND (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date='$EXPORT_DATE'::date"
[[ "$EXPORT_SCOPE" == "all_active_target" ]] && DATE_FILTER=""

if [[ "${JOBPUSH_CRAWL_COMPLETE:-0}" != "1" ]]; then
  REMAINING_DUE="$("${PSQL[@]}" -qAt -c "SELECT count(*) FROM jobpush.crawl_schedule_queue WHERE is_due AND crawl_status <> 'running';")"
  if (( REMAINING_DUE > 0 )); then
    echo "Daily export withheld: $REMAINING_DUE due sites remain after the crawl." >&2
    exit 1
  fi
fi

JSON_LINES="$WORK_DIR/jobs.jsonl"
TARGETS="$WORK_DIR/jd_targets.csv"
RESULTS="$WORK_DIR/jd_results.csv"
SCRAPE_REPORT="$WORK_DIR/jd_report.json"
EXPORT_JSON="$EXPORT_DIR/$EXPORT_DATE.json"
REPORT_JSON="$EXPORT_DIR/$EXPORT_DATE.report.json"
SES_REQUEST="$WORK_DIR/ses_request.json"
EMAIL_FILES="$WORK_DIR/email_files"

if [[ "$SKIP_JD_FETCH" == "1" ]]; then
  printf '%s\n' 'site_id,external_job_id,source_fingerprint,source_type,source_key,company,title,location,employment_type,posted_text,job_url,first_seen_date' > "$TARGETS"
elif [[ -n "$JD_INPUT_FILE" ]]; then
  cp "$JD_INPUT_FILE" "$TARGETS"
else
  "${PSQL[@]}" -v ON_ERROR_STOP=1 -c "\copy (
  WITH candidates AS (
    SELECT posting.site_id,posting.external_job_id,site.source_type,site.source_key,target.canonical_name AS company,
           posting.title,COALESCE(posting.location,'') AS location,
           COALESCE(posting.employment_type,'') AS employment_type,
           COALESCE(posting.posted_text,'') AS posted_text,posting.job_url,
           (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date AS first_seen_date,
           md5(concat_ws(E'\\x1f','$JD_PARSER_VERSION',posting.title,posting.location,posting.category,posting.job_url,
               posting.description_snippet,posting.posted_text,posting.employment_type)) AS source_fingerprint,
           snapshot.source_fingerprint AS saved_fingerprint,snapshot.scrape_status,snapshot.attempt_count
    FROM jobpush.job_postings_us posting
    JOIN jobpush.career_sites site USING(site_id)
    JOIN jobpush.crawl_targets target ON target.consolidation_key=posting.consolidation_key
    JOIN jobpush.job_title_labels label USING(normalized_title)
    LEFT JOIN jobpush.job_description_snapshots snapshot USING(site_id,external_job_id)
    WHERE posting.active AND label.classification_status='target' $DATE_FILTER
  )
  SELECT DISTINCT ON (job_url)
         site_id,external_job_id,source_fingerprint,source_type,source_key,company,title,location,
         employment_type,posted_text,job_url,first_seen_date
  FROM candidates
  WHERE saved_fingerprint IS NULL OR saved_fingerprint<>source_fingerprint
     OR (scrape_status='failed' AND attempt_count<9)
  ORDER BY job_url,
           (saved_fingerprint=source_fingerprint AND scrape_status='succeeded') DESC NULLS LAST,
           site_id,external_job_id
  LIMIT NULLIF('$JD_LIMIT','0')::integer
) TO '$TARGETS' WITH (FORMAT csv, HEADER true)"
fi

TO_FETCH=$(( $(wc -l < "$TARGETS") - 1 ))
if (( TO_FETCH > 0 )); then
  python3 "$REPO_DIR/scripts/enrich_job_descriptions.py" \
    "$TARGETS" "$RESULTS" "$SCRAPE_REPORT" --workers "$WORKERS"
  "${PSQL[@]}" -v ON_ERROR_STOP=1 <<SQL
BEGIN;
CREATE TEMP TABLE jd_stage (
  site_id BIGINT,external_job_id TEXT,source_fingerprint TEXT,source_type TEXT,source_key TEXT,company TEXT,title TEXT,
  location TEXT,employment_type TEXT,posted_text TEXT,job_url TEXT,first_seen_date DATE,
  raw_html TEXT,cleaned_description TEXT,content_type TEXT,apply_url TEXT,work_arrangement TEXT,
  salary_text TEXT,posted_date DATE,scraped_at TIMESTAMPTZ,scrape_status TEXT,scrape_error TEXT,
  http_status INTEGER,attempt_count INTEGER
) ON COMMIT DROP;
\copy jd_stage FROM '$RESULTS' WITH (FORMAT csv, HEADER true)
INSERT INTO jobpush.job_description_snapshots (
  site_id,external_job_id,source_fingerprint,raw_html,cleaned_description,content_type,
  apply_url,work_arrangement,salary_text,posted_date,scrape_status,scrape_error,
  http_status,attempt_count,scraped_at,updated_at
)
SELECT site_id,external_job_id,source_fingerprint,NULLIF(raw_html,''),NULLIF(cleaned_description,''),
       NULLIF(content_type,''),NULLIF(apply_url,''),NULLIF(work_arrangement,''),NULLIF(salary_text,''),
       posted_date,scrape_status,NULLIF(scrape_error,''),NULLIF(http_status,0),attempt_count,scraped_at,now()
FROM jd_stage
ON CONFLICT(site_id,external_job_id) DO UPDATE SET
  source_fingerprint=EXCLUDED.source_fingerprint,raw_html=EXCLUDED.raw_html,
  cleaned_description=EXCLUDED.cleaned_description,content_type=EXCLUDED.content_type,
  apply_url=EXCLUDED.apply_url,work_arrangement=EXCLUDED.work_arrangement,
  salary_text=EXCLUDED.salary_text,posted_date=EXCLUDED.posted_date,
  scrape_status=EXCLUDED.scrape_status,scrape_error=EXCLUDED.scrape_error,http_status=EXCLUDED.http_status,
  attempt_count=CASE WHEN jobpush.job_description_snapshots.source_fingerprint=EXCLUDED.source_fingerprint
    THEN jobpush.job_description_snapshots.attempt_count+EXCLUDED.attempt_count ELSE EXCLUDED.attempt_count END,
  scraped_at=EXCLUDED.scraped_at,updated_at=now();
COMMIT;
SQL
else
  printf '%s\n' '{"processed":0,"succeeded":0,"failed":0,"by_ats":{},"failure_reasons":{}}' > "$SCRAPE_REPORT"
fi

if [[ "$SKIP_EXPORT" == "1" ]]; then
  (( TO_FETCH > 0 )) && exit 0
  exit 10
fi

"${PSQL[@]}" -qAt -v ON_ERROR_STOP=1 -c "
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'company', target.canonical_name,
    'title', posting.title,
    'location', NULLIF(posting.location,''),
    'category', NULLIF(posting.category,''),
    'employment_type', NULLIF(posting.employment_type,''),
    'complete_job_description', CASE WHEN snapshot.scrape_status='succeeded' THEN snapshot.cleaned_description END,
    'description_complete', snapshot.scrape_status='succeeded',
    'description_fallback', CASE WHEN snapshot.scrape_status<>'succeeded' OR snapshot.scrape_status IS NULL THEN NULLIF(posting.description_snippet,'') END,
    'posted_date', NULLIF(posting.posted_text,''),
    'first_seen_at', posting.first_seen_at,
    'job_url', posting.job_url,
    'role_family', label.canonical_role,
    'company_tier', target.priority_tier,
    'apply_url', snapshot.apply_url,
    'work_arrangement', snapshot.work_arrangement,
    'salary', snapshot.salary_text,
    'jd_scraped_at', snapshot.scraped_at,
    'jd_scrape_status', snapshot.scrape_status,
    'jd_scrape_error', snapshot.scrape_error
  ))::text
  FROM jobpush.job_postings_us posting
  JOIN jobpush.crawl_targets target USING(consolidation_key)
  JOIN jobpush.job_title_labels label USING(normalized_title)
  JOIN jobpush.job_description_snapshots snapshot
    ON snapshot.site_id=posting.site_id AND snapshot.external_job_id=posting.external_job_id
   AND snapshot.source_fingerprint=md5(concat_ws(E'\\x1f','$JD_PARSER_VERSION',posting.title,posting.location,posting.category,
       posting.job_url,posting.description_snippet,posting.posted_text,posting.employment_type))
   AND snapshot.scrape_status='succeeded'
  WHERE posting.active
    AND label.classification_status='target'
    -- Require a complete JD and remove only explicit no-sponsorship language.
    -- A single occurrence of "visa" or "sponsor" never excludes a job.
    AND NOT jobpush.is_explicit_no_sponsorship(snapshot.cleaned_description)
    $DATE_FILTER
  ORDER BY posting.first_seen_at DESC, target.canonical_name, posting.title
" > "$JSON_LINES"

# A posting may temporarily exist under more than one site record while site
# consolidation catches up. Never send or process the same job URL twice.
jq -s 'unique_by(.job_url)' "$JSON_LINES" > "$EXPORT_JSON"
EXPORTED="$(jq length "$EXPORT_JSON")"
FULL_JD="$(jq '[.[]|select(.description_complete==true)]|length' "$EXPORT_JSON")"
FAILED_JD=$(( EXPORTED - FULL_JD ))
jq -n --arg date "$EXPORT_DATE" --arg scope "$EXPORT_SCOPE" --argjson exported "$EXPORTED" \
  --argjson full_jd "$FULL_JD" --argjson failed_jd "$FAILED_JD" \
  '{export_date:$date,scope:$scope,exported_jobs:$exported,complete_job_descriptions:$full_jd,incomplete_job_descriptions:$failed_jd}' > "$REPORT_JSON"

EMAIL_STATUS="pending"
EMAIL_ERROR=""
FILE_SIZE="$(stat -c %s "$EXPORT_JSON" 2>/dev/null || stat -f %z "$EXPORT_JSON")"
if [[ "$SKIP_EMAIL" == "1" ]]; then
  EMAIL_STATUS="skipped"
else
  if (( FILE_SIZE > MAX_ATTACHMENT_BYTES )); then
    python3 "$REPO_DIR/scripts/split_json_export.py" "$EXPORT_JSON" "$EMAIL_FILES"
  else
    printf '%s\n' "$EXPORT_JSON" > "$EMAIL_FILES"
  fi
  mapfile -t ATTACHMENTS < "$EMAIL_FILES"
  EMAIL_STATUS="sent"
  for index in "${!ATTACHMENTS[@]}"; do
    part=""
    (( ${#ATTACHMENTS[@]} > 1 )) && part="$((index + 1)) of ${#ATTACHMENTS[@]}"
    python3 "$REPO_DIR/scripts/build_ses_attachment_request.py" \
      "${ATTACHMENTS[$index]}" "$REPORT_JSON" "$SES_REQUEST" \
      --sender "$EMAIL_FROM" --recipients "$EMAIL_TO" --date "$EXPORT_DATE" --part "$part"
    if ! aws sesv2 send-email --region us-east-2 --cli-input-json "file://$SES_REQUEST" >/dev/null 2>"$WORK_DIR/email_error"; then
      EMAIL_STATUS="failed"
      EMAIL_ERROR="$(tail -c 1000 "$WORK_DIR/email_error")"
      break
    fi
  done
fi

"${PSQL[@]}" -v ON_ERROR_STOP=1 -v export_date="$EXPORT_DATE" -v export_path="$EXPORT_JSON" \
  -v exported="$EXPORTED" -v full_jd="$FULL_JD" -v failed_jd="$FAILED_JD" -v scope="$EXPORT_SCOPE" -v email_status="$EMAIL_STATUS" -v email_error="$EMAIL_ERROR" <<'SQL'
INSERT INTO jobpush.daily_job_exports(
  export_date,status,export_path,jobs_discovered,jobs_processed,successful_jd_retrieval,
  skipped_jobs,failed_jobs,exported_jobs,report,email_status,email_error,started_at,finished_at
) VALUES (
  :'export_date',CASE WHEN :failed_jd=0 THEN 'succeeded' ELSE 'partial' END,:'export_path',:exported,:exported,:full_jd,0,:failed_jd,:exported,
  jsonb_build_object('scope',:'scope','exported_jobs',:exported,'complete_job_descriptions',:full_jd,'incomplete_job_descriptions',:failed_jd),
  :'email_status',NULLIF(:'email_error',''),now(),now()
)
ON CONFLICT(export_date) DO UPDATE SET
  status=EXCLUDED.status,export_path=EXCLUDED.export_path,jobs_discovered=EXCLUDED.jobs_discovered,
  jobs_processed=EXCLUDED.jobs_processed,successful_jd_retrieval=EXCLUDED.successful_jd_retrieval,skipped_jobs=0,failed_jobs=EXCLUDED.failed_jobs,
  exported_jobs=EXCLUDED.exported_jobs,report=EXCLUDED.report,email_status=EXCLUDED.email_status,
  email_error=EXCLUDED.email_error,started_at=now(),finished_at=now();
SQL

echo "Daily target export complete: date=$EXPORT_DATE scope=$EXPORT_SCOPE jobs=$EXPORTED full_jd=$FULL_JD incomplete_jd=$FAILED_JD email=$EMAIL_STATUS"
