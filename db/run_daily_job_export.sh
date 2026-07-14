#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

EXPORT_DATE="${1:-$(TZ=America/Chicago date +%F)}"
EXPORT_DIR="${JOBPUSH_DAILY_EXPORT_DIR:-$REPO_DIR/daily_exports}"
WORKERS="${JOBPUSH_JD_WORKERS:-8}"
TARGET_LIMIT="${JOBPUSH_JD_LIMIT:-0}"
EMAIL_TO="${JOBPUSH_EXPORT_EMAIL:-nicole732470@gmail.com,yuli2026@u.northwestern.edu}"
EMAIL_FROM="${JOBPUSH_EXPORT_FROM_EMAIL:-nicole732470@gmail.com}"
MAX_ATTACHMENT_BYTES="${JOBPUSH_MAX_EMAIL_ATTACHMENT_BYTES:-24000000}"
WORK_DIR="$(mktemp -d -t jobpush-daily-export.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

TARGETS="$WORK_DIR/targets.csv"
RESULTS="$WORK_DIR/results.csv"
SCRAPE_REPORT="$WORK_DIR/scrape_report.json"
EXPORT_CSV="$WORK_DIR/export.csv"
EXPORT_JSON="$EXPORT_DIR/$EXPORT_DATE.json"
REPORT_JSON="$EXPORT_DIR/$EXPORT_DATE.report.json"
SES_REQUEST="$WORK_DIR/ses_request.json"

mkdir -p "$EXPORT_DIR"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -v export_date="$EXPORT_DATE" <<'SQL'
INSERT INTO jobpush.daily_job_exports(export_date,status,started_at,finished_at,email_status,email_error)
VALUES (:'export_date','running',now(),NULL,NULL,NULL)
ON CONFLICT(export_date) DO UPDATE SET status='running',started_at=now(),finished_at=NULL,email_status=NULL,email_error=NULL;
SQL

"${PSQL[@]}" -v ON_ERROR_STOP=1 -v export_date="$EXPORT_DATE" -v target_limit="$TARGET_LIMIT" -c "\copy (
  WITH candidates AS (
    SELECT posting.*, site.source_type, target.canonical_name AS company,
           md5(concat_ws(E'\\x1f', posting.title, posting.location, posting.category,
               posting.job_url, posting.description_snippet, posting.posted_text, posting.employment_type)) AS source_fingerprint
    FROM jobpush.job_postings posting
    JOIN jobpush.career_sites site USING(site_id)
    JOIN jobpush.crawl_targets target USING(consolidation_key)
    WHERE posting.active
      AND (
        (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date = :'export_date'::date
        OR EXISTS (
          SELECT 1 FROM jobpush.job_description_snapshots snapshot
          WHERE snapshot.site_id=posting.site_id AND snapshot.external_job_id=posting.external_job_id
            AND (
              snapshot.source_fingerprint<>md5(concat_ws(E'\\x1f', posting.title, posting.location, posting.category,
                  posting.job_url, posting.description_snippet, posting.posted_text, posting.employment_type))
              OR (snapshot.scrape_status='failed' AND snapshot.attempt_count < 9)
            )
        )
      )
  )
  SELECT site_id,external_job_id,source_fingerprint,source_type,company,title,
         COALESCE(location,'') AS location,COALESCE(employment_type,'') AS employment_type,
         COALESCE(posted_text,'') AS posted_text,job_url,
         (first_seen_at AT TIME ZONE 'America/Chicago')::date AS first_seen_date
  FROM candidates ORDER BY first_seen_at,site_id,external_job_id
  LIMIT NULLIF(:'target_limit','0')::integer
) TO '$TARGETS' WITH (FORMAT csv, HEADER true)"

DISCOVERED="$("${PSQL[@]}" -qAt -v export_date="$EXPORT_DATE" -c \
  "SELECT count(*) FROM jobpush.job_postings WHERE active AND (first_seen_at AT TIME ZONE 'America/Chicago')::date=:'export_date'::date;")"
PROCESSED=$(( $(wc -l < "$TARGETS") - 1 ))
SKIPPED=$(( DISCOVERED > PROCESSED ? DISCOVERED - PROCESSED : 0 ))

if (( PROCESSED > 0 )); then
  python3 "$REPO_DIR/scripts/enrich_job_descriptions.py" \
    "$TARGETS" "$RESULTS" "$SCRAPE_REPORT" --workers "$WORKERS"

  "${PSQL[@]}" -v ON_ERROR_STOP=1 <<SQL
CREATE TEMP TABLE jd_stage (
  site_id BIGINT,external_job_id TEXT,source_fingerprint TEXT,source_type TEXT,company TEXT,title TEXT,
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
  scrape_status=EXCLUDED.scrape_status,scrape_error=EXCLUDED.scrape_error,
  http_status=EXCLUDED.http_status,
  attempt_count=CASE
    WHEN jobpush.job_description_snapshots.source_fingerprint=EXCLUDED.source_fingerprint
      THEN jobpush.job_description_snapshots.attempt_count+EXCLUDED.attempt_count
    ELSE EXCLUDED.attempt_count
  END,
  scraped_at=EXCLUDED.scraped_at,updated_at=now();
SQL
else
  printf '%s\n' '{"processed":0,"succeeded":0,"failed":0,"by_ats":{},"failure_reasons":{}}' > "$SCRAPE_REPORT"
fi

"${PSQL[@]}" -v ON_ERROR_STOP=1 -v export_date="$EXPORT_DATE" -c "\copy (
  SELECT target.canonical_name AS company,posting.title,COALESCE(posting.location,'') AS location,
         COALESCE(snapshot.work_arrangement,'') AS work_arrangement,
         COALESCE(posting.employment_type,'') AS employment_type,
         COALESCE(snapshot.salary_text,'') AS salary_text,
         COALESCE(snapshot.posted_date::text,'') AS posted_date,COALESCE(posting.posted_text,'') AS posted_text,
         (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date AS first_seen_date,
         posting.job_url,COALESCE(snapshot.apply_url,'') AS apply_url,site.source_type,
         snapshot.cleaned_description,snapshot.raw_html,snapshot.scrape_status,
         snapshot.scraped_at,snapshot.http_status,snapshot.attempt_count,
         COALESCE(snapshot.scrape_error,'') AS scrape_error,COALESCE(snapshot.content_type,'') AS content_type,
         snapshot.source_fingerprint
  FROM jobpush.job_postings posting
  JOIN jobpush.job_description_snapshots snapshot USING(site_id,external_job_id)
  JOIN jobpush.career_sites site USING(site_id)
  JOIN jobpush.crawl_targets target USING(consolidation_key)
  WHERE posting.active AND snapshot.scrape_status='succeeded'
    AND (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date=:'export_date'::date
  ORDER BY posting.first_seen_at,posting.site_id,posting.external_job_id
) TO '$EXPORT_CSV' WITH (FORMAT csv, HEADER true)"

python3 "$REPO_DIR/scripts/build_daily_job_export.py" \
  "$EXPORT_CSV" "$EXPORT_JSON" "$SCRAPE_REPORT" "$REPORT_JSON" \
  --discovered "$DISCOVERED" --processed "$PROCESSED" --skipped "$SKIPPED"

REPORT_COMPACT="$(jq -c . "$REPORT_JSON")"
EXPORTED="$(jq -r .exported_jobs "$REPORT_JSON")"
SUCCEEDED="$(jq -r .successful_jd_retrieval "$REPORT_JSON")"
FAILED="$(jq -r .failed_jobs "$REPORT_JSON")"
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
  -v discovered="$DISCOVERED" -v processed="$PROCESSED" -v succeeded="$SUCCEEDED" \
  -v skipped="$SKIPPED" -v failed="$FAILED" -v exported="$EXPORTED" \
  -v report="$REPORT_COMPACT" -v email_status="$EMAIL_STATUS" -v email_error="$EMAIL_ERROR" <<'SQL'
UPDATE jobpush.daily_job_exports
SET status=CASE WHEN :'failed'::int=0 THEN 'succeeded' ELSE 'partial' END,
    export_path=:'export_path',jobs_discovered=:discovered,jobs_processed=:processed,
    successful_jd_retrieval=:succeeded,skipped_jobs=:skipped,failed_jobs=:failed,
    exported_jobs=:exported,report=:'report'::jsonb,email_status=:'email_status',
    email_error=NULLIF(:'email_error',''),finished_at=now()
WHERE export_date=:'export_date';
SQL

echo "Daily export complete: path=$EXPORT_JSON size=$FILE_SIZE discovered=$DISCOVERED processed=$PROCESSED exported=$EXPORTED failed=$FAILED email=$EMAIL_STATUS"
