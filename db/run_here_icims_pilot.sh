#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

CONSOLIDATION_KEY="77-0080465"
SITE_URL="https://careers-here.icims.com/jobs/search?ss=1&hashed=-435626304"
BATCH_NAME="here-icims-pilot-$(date -u +%Y%m%dT%H%M%SZ)"
JOBS_CSV="$(mktemp /tmp/here-icims-jobs.XXXXXX)"
METRICS_JSON="$(mktemp /tmp/here-icims-metrics.XXXXXX)"
trap 'rm -f "$JOBS_CSV" "$METRICS_JSON"' EXIT

SITE_ID=$("${PSQL[@]}" -Atc \
  "SELECT site_id FROM jobpush.career_sites
   WHERE consolidation_key = '$CONSOLIDATION_KEY'
     AND verification_status = 'verified' AND crawl_enabled AND source_type = 'icims'
   ORDER BY site_id LIMIT 1;")
[[ -n "$SITE_ID" ]] || { echo "No verified enabled HERE iCIMS site found" >&2; exit 1; }

# A shell/transport interruption before a run row exists must not leave a batch
# looking active forever. This only touches this one-company pilot cohort.
"${PSQL[@]}" -q -c \
  "UPDATE jobpush.crawl_batches
   SET status='failed', failed_target_count=GREATEST(failed_target_count, 1),
       finished_at=COALESCE(finished_at, now())
   WHERE cohort='p0-adapter-pilot' AND status='running';"

BATCH_ID=$("${PSQL[@]}" -Atc \
  "INSERT INTO jobpush.crawl_batches
       (batch_name, cohort, priority_tier, selection_rule, status,
        planned_target_count, attempted_target_count, started_at)
   VALUES ('$BATCH_NAME', 'p0-adapter-pilot', 'P0',
           'Manually verified P0 site; one company adapter smoke test',
           'running', 1, 1, now()) RETURNING batch_id;" | sed -n '1p')

"${PSQL[@]}" -q -c \
  "INSERT INTO jobpush.crawl_batch_targets
       (batch_id, consolidation_key, site_id, status)
   VALUES ($BATCH_ID, '$CONSOLIDATION_KEY', $SITE_ID, 'running');"

RUN_ID=$("${PSQL[@]}" -Atc \
  "INSERT INTO jobpush.crawl_runs
       (batch_id, site_id, adapter_name, adapter_version, status, crawl_scope, scope_method)
   VALUES ($BATCH_ID, $SITE_ID, 'icims-html', '0.2.0', 'running', 'US', 'server_filter') RETURNING run_id;" | sed -n '1p')

fail_run() {
  local exit_code=$?
  local message="iCIMS pilot failed with exit code $exit_code"
  "${PSQL[@]}" -q -c \
    "UPDATE jobpush.crawl_runs SET status='failed', error_code='pilot_failure',
            error_message='$message', finished_at=now() WHERE run_id=$RUN_ID;
     UPDATE jobpush.crawl_batch_targets SET status='failed'
       WHERE batch_id=$BATCH_ID AND site_id=$SITE_ID;
     UPDATE jobpush.crawl_batches SET status='failed', failed_target_count=1,
            finished_at=now() WHERE batch_id=$BATCH_ID;
     UPDATE jobpush.career_sites SET crawl_status='failed',
            consecutive_failures=consecutive_failures+1, last_error='$message',
            last_crawled_at=now(), updated_at=now() WHERE site_id=$SITE_ID;" || true
  exit "$exit_code"
}
trap fail_run ERR

python3 "$REPO_DIR/scripts/crawl_icims.py" --url "$SITE_URL" --output "$JOBS_CSV" --country US > "$METRICS_JSON"

IFS=$'\t' read -r REQUESTS PAGES RAW_COUNT PARSED_COUNT DUPLICATES HTTP_STATUS LATENCY_MS < <(
  python3 - "$METRICS_JSON" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
print("\t".join(str(data[key]) for key in (
    "requests_count", "pages_fetched", "raw_job_count", "parsed_job_count",
    "duplicate_count", "last_http_status", "latency_ms"
)))
PY
)

"${PSQL[@]}" <<SQL
BEGIN;
CREATE TEMP TABLE crawl_stage (
    external_job_id TEXT, title TEXT, normalized_title TEXT, location TEXT,
    category TEXT, job_url TEXT, description_snippet TEXT
) ON COMMIT DROP;
\copy crawl_stage FROM '$JOBS_CSV' WITH (FORMAT csv, HEADER true)

WITH counts AS (
    SELECT count(*) FILTER (WHERE p.external_job_id IS NULL) AS new_count,
           count(*) FILTER (WHERE p.external_job_id IS NOT NULL) AS updated_count
    FROM crawl_stage s LEFT JOIN jobpush.job_postings p
      ON p.site_id=$SITE_ID AND p.external_job_id=s.external_job_id
), closed AS (
    SELECT count(*) AS closed_count FROM jobpush.job_postings p
    WHERE p.site_id=$SITE_ID AND p.active AND p.market_scope='US'
      AND NOT EXISTS (SELECT 1 FROM crawl_stage s WHERE s.external_job_id=p.external_job_id)
)
UPDATE jobpush.crawl_runs r
SET new_job_count=counts.new_count, updated_job_count=counts.updated_count,
    closed_job_count=closed.closed_count
FROM counts, closed WHERE r.run_id=$RUN_ID;

INSERT INTO jobpush.job_postings (
    site_id, external_job_id, consolidation_key, title, normalized_title,
    location, category, job_url, description_snippet, active,
    first_seen_at, last_seen_at, closed_at, last_run_id, updated_at
)
SELECT $SITE_ID, s.external_job_id, '$CONSOLIDATION_KEY', s.title, s.normalized_title,
       NULLIF(s.location,''), NULLIF(s.category,''), s.job_url,
       NULLIF(s.description_snippet,''), TRUE, now(), now(), NULL, $RUN_ID, now()
FROM crawl_stage s
ON CONFLICT (site_id, external_job_id) DO UPDATE SET
    title=EXCLUDED.title, normalized_title=EXCLUDED.normalized_title,
    location=EXCLUDED.location, category=EXCLUDED.category,
    job_url=EXCLUDED.job_url, description_snippet=EXCLUDED.description_snippet,
    active=TRUE, last_seen_at=now(), closed_at=NULL, last_run_id=$RUN_ID, updated_at=now();

UPDATE jobpush.job_postings p
SET active=FALSE, closed_at=now(), last_run_id=$RUN_ID, updated_at=now()
WHERE p.site_id=$SITE_ID AND p.active AND p.market_scope='US'
  AND NOT EXISTS (SELECT 1 FROM crawl_stage s WHERE s.external_job_id=p.external_job_id);

INSERT INTO jobpush.job_title_labels (normalized_title)
SELECT DISTINCT normalized_title FROM crawl_stage ON CONFLICT DO NOTHING;

UPDATE jobpush.crawl_runs r
SET status='succeeded', requests_count=$REQUESTS, pages_fetched=$PAGES,
    last_http_status=$HTTP_STATUS, latency_ms=$LATENCY_MS,
    raw_job_count=$RAW_COUNT, parsed_job_count=$PARSED_COUNT,
    duplicate_count=$DUPLICATES,
    target_job_count=(SELECT count(*) FROM crawl_stage s JOIN jobpush.job_title_labels l USING(normalized_title) WHERE l.classification_status='target'),
    review_job_count=(SELECT count(*) FROM crawl_stage s JOIN jobpush.job_title_labels l USING(normalized_title) WHERE l.classification_status='review'),
    finished_at=now()
WHERE r.run_id=$RUN_ID;

UPDATE jobpush.crawl_batch_targets SET status='succeeded'
WHERE batch_id=$BATCH_ID AND site_id=$SITE_ID;
UPDATE jobpush.crawl_batches b
SET status='succeeded', successful_target_count=1, requests_count=$REQUESTS,
    discovered_job_count=$PARSED_COUNT,
    target_job_count=(SELECT target_job_count FROM jobpush.crawl_runs WHERE run_id=$RUN_ID),
    review_job_count=(SELECT review_job_count FROM jobpush.crawl_runs WHERE run_id=$RUN_ID),
    finished_at=now()
WHERE b.batch_id=$BATCH_ID;
UPDATE jobpush.career_sites
SET crawl_status='succeeded', last_crawled_at=now(), last_success_at=now(),
    consecutive_failures=0, last_error=NULL, updated_at=now()
WHERE site_id=$SITE_ID;
COMMIT;
SQL

trap - ERR
"${PSQL[@]}" -P pager=off -c \
  "SELECT b.batch_id, b.batch_name, b.status, b.requests_count,
          b.discovered_job_count, b.target_job_count, b.review_job_count,
          r.pages_fetched, r.latency_ms, r.new_job_count,
          r.updated_job_count, r.closed_job_count
   FROM jobpush.crawl_batches b JOIN jobpush.crawl_runs r USING(batch_id)
   WHERE b.batch_id=$BATCH_ID;
   SELECT external_job_id, title, location, category, job_url
   FROM jobpush.job_postings WHERE site_id=$SITE_ID AND active
   ORDER BY external_job_id DESC LIMIT 10;"
