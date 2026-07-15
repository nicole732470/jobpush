#!/usr/bin/env bash
set -euo pipefail

: "${CONSOLIDATION_KEY:?}"
: "${SOURCE_TYPE:?}"
: "${ADAPTER_NAME:?}"
: "${ADAPTER_VERSION:?}"
: "${ADAPTER_SCRIPT:?}"
: "${COHORT:?}"
: "${PRIORITY_TIER:?}"
: "${SCOPE_METHOD:?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

JOBS_CSV="$(mktemp /tmp/jobpush-adapter-jobs.XXXXXX)"
METRICS_JSON="$(mktemp /tmp/jobpush-adapter-metrics.XXXXXX)"
ADAPTER_STDERR="$(mktemp /tmp/jobpush-adapter-stderr.XXXXXX)"
MISSING_JOBS_CSV="$(mktemp /tmp/jobpush-missing-jobs.XXXXXX)"
CONFIRMED_CLOSED_CSV="$(mktemp /tmp/jobpush-confirmed-closed.XXXXXX)"
CLOSURE_METRICS_JSON="$(mktemp /tmp/jobpush-closure-metrics.XXXXXX)"
trap 'rm -f "$JOBS_CSV" "$METRICS_JSON" "$ADAPTER_STDERR" "$MISSING_JOBS_CSV" "$CONFIRMED_CLOSED_CSV" "$CLOSURE_METRICS_JSON"' EXIT

SITE_FILTER=""
if [[ -n "${SITE_ID:-}" ]]; then
  SITE_FILTER="AND site_id=$SITE_ID"
fi
IFS=$'\t' read -r SITE_ID SITE_URL < <("${PSQL[@]}" -qAtF $'\t' -c \
  "SELECT site_id, site_url FROM jobpush.career_sites
   WHERE consolidation_key='$CONSOLIDATION_KEY' AND source_type='$SOURCE_TYPE'
     AND verification_status='verified' AND crawl_enabled
     $SITE_FILTER
   ORDER BY site_id LIMIT 1;")
[[ -n "${SITE_ID:-}" && -n "${SITE_URL:-}" ]] || { echo "No verified $SOURCE_TYPE site" >&2; exit 1; }

"${PSQL[@]}" -q -c \
  "UPDATE jobpush.crawl_batches SET status='failed',
      failed_target_count=GREATEST(failed_target_count,1), finished_at=COALESCE(finished_at,now())
   WHERE cohort='$COHORT' AND status='running'
     AND started_at < now() - interval '2 hours';"

BATCH_NAME="$COHORT-site${SITE_ID}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
BATCH_ID=$("${PSQL[@]}" -Atc \
  "INSERT INTO jobpush.crawl_batches
      (batch_name,cohort,priority_tier,selection_rule,status,
       planned_target_count,attempted_target_count,started_at)
   VALUES ('$BATCH_NAME','$COHORT','$PRIORITY_TIER',
           'One verified site representative for adapter validation',
           'running',1,1,now()) RETURNING batch_id;" | sed -n '1p')
"${PSQL[@]}" -q -c \
  "INSERT INTO jobpush.crawl_batch_targets(batch_id,consolidation_key,site_id,status)
   VALUES ($BATCH_ID,'$CONSOLIDATION_KEY',$SITE_ID,'running');"
RUN_ID=$("${PSQL[@]}" -Atc \
  "INSERT INTO jobpush.crawl_runs
      (batch_id,site_id,adapter_name,adapter_version,status,crawl_scope,scope_method)
   VALUES ($BATCH_ID,$SITE_ID,'$ADAPTER_NAME','$ADAPTER_VERSION','running','US','$SCOPE_METHOD')
   RETURNING run_id;" | sed -n '1p')

fail_run() {
  local code=$?
  local error_text
  error_text=$(tail -c 900 "$ADAPTER_STDERR" 2>/dev/null | sed "s/'/''/g" || true)
  if [[ -z "$error_text" ]]; then
    error_text="Adapter pilot failed with exit code $code"
  fi
  "${PSQL[@]}" -q -c \
    "UPDATE jobpush.crawl_runs SET status='failed',error_code='pilot_failure',
       error_message='$error_text',finished_at=now() WHERE run_id=$RUN_ID;
     UPDATE jobpush.crawl_batch_targets SET status='failed' WHERE batch_id=$BATCH_ID AND site_id=$SITE_ID;
     UPDATE jobpush.crawl_batches SET status='failed',failed_target_count=1,finished_at=now() WHERE batch_id=$BATCH_ID;
     UPDATE jobpush.career_sites SET crawl_status='failed',consecutive_failures=consecutive_failures+1,
       last_error='$error_text',last_crawled_at=now(),
       next_crawl_at=now()+make_interval(hours => LEAST(24, GREATEST(1, power(2, consecutive_failures)::int))),
       updated_at=now()
       WHERE site_id=$SITE_ID;" || true
  exit "$code"
}
trap fail_run ERR

if [[ "$SOURCE_TYPE" == "icims" ]]; then
  ICIMS_TIMEOUT="${ICIMS_CRAWL_TIMEOUT:-30}"
  python3 "$REPO_DIR/$ADAPTER_SCRIPT" --url "$SITE_URL" --output "$JOBS_CSV" --country US --timeout "$ICIMS_TIMEOUT" > "$METRICS_JSON" 2> "$ADAPTER_STDERR"
elif [[ "$SOURCE_TYPE" == "generic_html" ]]; then
  python3 "$REPO_DIR/$ADAPTER_SCRIPT" --url "$SITE_URL" --output "$JOBS_CSV" > "$METRICS_JSON" 2> "$ADAPTER_STDERR"
elif [[ "$SCOPE_METHOD" == "local_filter" ]]; then
  python3 "$REPO_DIR/$ADAPTER_SCRIPT" --url "$SITE_URL" --output "$JOBS_CSV" --default-market unknown > "$METRICS_JSON" 2> "$ADAPTER_STDERR"
else
  python3 "$REPO_DIR/$ADAPTER_SCRIPT" --url "$SITE_URL" --output "$JOBS_CSV" --default-market US > "$METRICS_JSON" 2> "$ADAPTER_STDERR"
fi
IFS=$'\t' read -r REQUESTS PAGES RAW_COUNT PARSED_COUNT DUPLICATES HTTP_STATUS LATENCY_MS SOURCE_FILTERED < <(
  python3 - "$METRICS_JSON" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
print("\t".join(str(d[k]) for k in ("requests_count","pages_fetched","raw_job_count",
      "parsed_job_count","duplicate_count","last_http_status","latency_ms")) +
      "\t" + str(d.get("source_filtered", False)).lower())
PY
)

# A temporary parser/API regression must not close every previously active job.
ACTIVE_JOB_COUNT="$("${PSQL[@]}" -qAt -c \
  "SELECT count(*) FROM jobpush.job_postings WHERE site_id=$SITE_ID AND active AND market_scope='US';")"
if (( PARSED_COUNT == 0 && ACTIVE_JOB_COUNT > 0 )); then
  echo "zero-result guard: parser returned 0 jobs for a site with $ACTIVE_JOB_COUNT active US jobs" > "$ADAPTER_STDERR"
  false
fi

"${PSQL[@]}" -v source_filtered="$SOURCE_FILTERED" <<SQL
BEGIN;
CREATE TEMP TABLE crawl_stage (
  external_job_id TEXT,title TEXT,normalized_title TEXT,location TEXT,category TEXT,
  job_url TEXT,description_snippet TEXT,market_scope TEXT,posted_text TEXT,employment_type TEXT
) ON COMMIT DROP;
\copy crawl_stage FROM '$JOBS_CSV' WITH (FORMAT csv, HEADER true)

-- ponytail: coarse pre-storage filter; add a real sponsorship flag only after
-- target/review description fetching exists.
DELETE FROM crawl_stage
WHERE market_scope IS DISTINCT FROM 'US'
   OR COALESCE(description_snippet, '') ~* '(no|not).{0,50}(visa|h-?1b|sponsor|sponsorship)|without.{0,60}sponsorship|authorized.{0,80}without.{0,40}sponsorship|will not.{0,50}sponsor';

-- ponytail: adapters sometimes return the same ATS id twice in one page/API
-- batch; dedupe before ON CONFLICT so one bad board does not fail the run.
DELETE FROM crawl_stage a
USING crawl_stage b
WHERE a.ctid < b.ctid
  AND a.external_job_id = b.external_job_id;

\if :source_filtered
\copy (SELECT p.external_job_id,p.job_url FROM jobpush.job_postings p WHERE false) TO '$MISSING_JOBS_CSV' WITH (FORMAT csv, HEADER true)
\! cp '$MISSING_JOBS_CSV' '$CONFIRMED_CLOSED_CSV'; printf '{"checked":0,"closed":0,"kept":0,"errors":0,"source_filtered":true}\n' > '$CLOSURE_METRICS_JSON'
\else
\copy (SELECT p.external_job_id,p.job_url FROM jobpush.job_postings p WHERE p.site_id=$SITE_ID AND p.active AND p.market_scope='US' AND NOT EXISTS (SELECT 1 FROM crawl_stage s WHERE s.external_job_id=p.external_job_id)) TO '$MISSING_JOBS_CSV' WITH (FORMAT csv, HEADER true)
\! python3 "$REPO_DIR/scripts/verify_closed_job_links.py" "$MISSING_JOBS_CSV" "$CONFIRMED_CLOSED_CSV" > "$CLOSURE_METRICS_JSON"
\endif

CREATE TEMP TABLE confirmed_closed (external_job_id TEXT PRIMARY KEY) ON COMMIT DROP;
\copy confirmed_closed FROM '$CONFIRMED_CLOSED_CSV' WITH (FORMAT csv, HEADER true)

WITH counts AS (
  SELECT count(*) FILTER (WHERE p.external_job_id IS NULL) new_count,
         count(*) FILTER (WHERE p.external_job_id IS NOT NULL) updated_count
  FROM crawl_stage s LEFT JOIN jobpush.job_postings p
    ON p.site_id=$SITE_ID AND p.external_job_id=s.external_job_id
), closed AS (
  SELECT count(*) AS closed_count
  FROM confirmed_closed closed
  JOIN jobpush.job_postings posting
    ON posting.site_id=$SITE_ID AND posting.external_job_id=closed.external_job_id
  JOIN jobpush.job_title_labels label USING(normalized_title)
  WHERE label.classification_status='target'
)
UPDATE jobpush.crawl_runs r SET new_job_count=counts.new_count,
  updated_job_count=counts.updated_count,closed_job_count=closed.closed_count
FROM counts,closed WHERE r.run_id=$RUN_ID;

INSERT INTO jobpush.job_postings (
  site_id,external_job_id,consolidation_key,title,normalized_title,location,category,
  job_url,description_snippet,market_scope,posted_text,employment_type,active,
  first_seen_at,last_seen_at,closed_at,last_run_id,updated_at)
SELECT $SITE_ID,s.external_job_id,'$CONSOLIDATION_KEY',s.title,s.normalized_title,
  NULLIF(s.location,''),NULLIF(s.category,''),s.job_url,NULLIF(s.description_snippet,''),
  s.market_scope,NULLIF(s.posted_text,''),NULLIF(s.employment_type,''),TRUE,
  now(),now(),NULL,$RUN_ID,now()
FROM crawl_stage s
ON CONFLICT(site_id,external_job_id) DO UPDATE SET
  title=EXCLUDED.title,normalized_title=EXCLUDED.normalized_title,location=EXCLUDED.location,
  category=EXCLUDED.category,job_url=EXCLUDED.job_url,
  description_snippet=EXCLUDED.description_snippet,market_scope=EXCLUDED.market_scope,
  posted_text=EXCLUDED.posted_text,employment_type=EXCLUDED.employment_type,
  active=TRUE,last_seen_at=now(),closed_at=NULL,closure_verified_at=NULL,
  last_run_id=$RUN_ID,updated_at=now();

UPDATE jobpush.job_postings p SET active=FALSE,closed_at=now(),closure_verified_at=now(),
  last_run_id=$RUN_ID,updated_at=now()
FROM confirmed_closed closed
WHERE p.site_id=$SITE_ID AND p.external_job_id=closed.external_job_id
  AND p.active AND p.market_scope='US';
\if :source_filtered
-- These jobs disappeared because the board's source scope was narrowed, not
-- because their links were verified closed. Retire them without fake closure
-- timestamps or thousands of detail-page requests.
UPDATE jobpush.job_postings p
SET active=FALSE,closed_at=NULL,closure_verified_at=NULL,last_run_id=$RUN_ID,updated_at=now()
WHERE p.site_id=$SITE_ID AND p.active
  AND NOT EXISTS (SELECT 1 FROM crawl_stage s WHERE s.external_job_id=p.external_job_id);

DELETE FROM jobpush.dashboard_jobs_fast fast
WHERE fast.site_id=$SITE_ID
  AND NOT EXISTS (
    SELECT 1 FROM jobpush.job_postings posting
    WHERE posting.site_id=fast.site_id
      AND posting.external_job_id=fast.external_job_id
      AND posting.active AND posting.market_scope='US'
  );
\endif
INSERT INTO jobpush.job_title_labels(normalized_title)
SELECT DISTINCT normalized_title FROM crawl_stage ON CONFLICT DO NOTHING;

UPDATE jobpush.crawl_runs r SET status='succeeded',requests_count=$REQUESTS,
  pages_fetched=$PAGES,last_http_status=$HTTP_STATUS,latency_ms=$LATENCY_MS,
  raw_job_count=$RAW_COUNT,parsed_job_count=$PARSED_COUNT,duplicate_count=$DUPLICATES,
  target_job_count=(SELECT count(*) FROM crawl_stage s JOIN jobpush.job_title_labels l USING(normalized_title) WHERE l.classification_status='target'),
  review_job_count=(SELECT count(*) FROM crawl_stage s JOIN jobpush.job_title_labels l USING(normalized_title) WHERE l.classification_status='review'),
  finished_at=now() WHERE r.run_id=$RUN_ID;
UPDATE jobpush.crawl_batch_targets SET status='succeeded' WHERE batch_id=$BATCH_ID AND site_id=$SITE_ID;
UPDATE jobpush.crawl_batches SET status='succeeded',successful_target_count=1,
  requests_count=$REQUESTS,discovered_job_count=$PARSED_COUNT,
  target_job_count=(SELECT target_job_count FROM jobpush.crawl_runs WHERE run_id=$RUN_ID),
  review_job_count=(SELECT review_job_count FROM jobpush.crawl_runs WHERE run_id=$RUN_ID),
  finished_at=now() WHERE batch_id=$BATCH_ID;
UPDATE jobpush.career_sites SET crawl_status='succeeded',last_crawled_at=now(),last_success_at=now(),
  next_crawl_at=now()+make_interval(hours => COALESCE(crawl_interval_hours, 168)),
  consecutive_failures=0,last_error=NULL,updated_at=now() WHERE site_id=$SITE_ID;
COMMIT;
SQL
trap - ERR

cat "$CLOSURE_METRICS_JSON"
"${PSQL[@]}" -P pager=off -c \
  "SELECT b.batch_id,b.batch_name,b.status,b.requests_count,b.discovered_job_count,
      b.target_job_count,b.review_job_count,r.pages_fetched,r.latency_ms,
      r.new_job_count,r.updated_job_count,r.closed_job_count
   FROM jobpush.crawl_batches b JOIN jobpush.crawl_runs r USING(batch_id)
   WHERE b.batch_id=$BATCH_ID;"
