#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DATE="${1:-$(TZ=America/Chicago date +%F)}"
BATCH_SIZE="${JOBPUSH_JD_BATCH_SIZE:-50}"
WORKERS="${JOBPUSH_JD_WORKERS:-4}"
JD_PARSER_VERSION="${JOBPUSH_JD_PARSER_VERSION:-jd-v2-complete-content}"
WORK_DIR="$(mktemp -d -t jobpush-jd-backfill.XXXXXX)"
QUEUE="$WORK_DIR/queue.csv"
BATCH="$WORK_DIR/batch.csv"
trap 'rm -rf "$WORK_DIR"' EXIT

source "$SCRIPT_DIR/lib/connect_rds.sh"

# Build the pending-job queue once. The old loop repeated this full join, hash,
# and sort before every 50 jobs, which became the dominant runtime.
"${PSQL[@]}" -v ON_ERROR_STOP=1 -c "\copy (
  WITH current_target_keys AS MATERIALIZED (
    SELECT fast.site_id,fast.external_job_id
    FROM jobpush.dashboard_jobs_fast fast
    WHERE fast.role_status='target'
  ), candidates AS (
    SELECT posting.site_id,posting.external_job_id,site.source_type,site.source_key,target.canonical_name AS company,
           posting.title,COALESCE(posting.location,'') AS location,
           COALESCE(posting.employment_type,'') AS employment_type,
           COALESCE(posting.posted_text,'') AS posted_text,posting.job_url,
           (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date AS first_seen_date,
           md5(concat_ws(E'\\x1f','$JD_PARSER_VERSION',posting.title,posting.location,posting.category,posting.job_url,
               posting.description_snippet,posting.posted_text,posting.employment_type)) AS source_fingerprint,
           snapshot.source_fingerprint AS saved_fingerprint,snapshot.scrape_status,snapshot.attempt_count
    FROM current_target_keys
    JOIN jobpush.job_postings posting USING(site_id,external_job_id)
    JOIN jobpush.career_sites site USING(site_id)
    JOIN jobpush.crawl_targets target ON target.consolidation_key=posting.consolidation_key
    LEFT JOIN jobpush.job_description_snapshots snapshot USING(site_id,external_job_id)
    WHERE posting.active AND posting.market_scope='US'
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
) TO '$QUEUE' WITH (FORMAT csv, HEADER true)"

TOTAL="$(python3 -c 'import csv,sys; print(sum(1 for _ in csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8"))))' "$QUEUE")"
echo "JD backfill queue ready: $TOTAL jobs"

offset=0
while (( offset < TOTAL )); do
  python3 "$SCRIPT_DIR/../scripts/slice_csv.py" "$QUEUE" "$BATCH" \
    --offset "$offset" --limit "$BATCH_SIZE"
  JOBPUSH_CRAWL_COMPLETE=1 JOBPUSH_EXPORT_SCOPE=all_active_target \
    JOBPUSH_JD_INPUT_FILE="$BATCH" JOBPUSH_JD_WORKERS="$WORKERS" JOBPUSH_SKIP_EXPORT=1 \
    bash "$SCRIPT_DIR/run_daily_job_export.sh" "$EXPORT_DATE"
  offset=$(( offset + BATCH_SIZE ))
  (( offset > TOTAL )) && offset="$TOTAL"
  echo "JD backfill persisted: $offset/$TOTAL"
done

JOBPUSH_CRAWL_COMPLETE=1 JOBPUSH_EXPORT_SCOPE=all_active_target JOBPUSH_SKIP_JD_FETCH=1 \
  bash "$SCRIPT_DIR/run_daily_job_export.sh" "$EXPORT_DATE"
