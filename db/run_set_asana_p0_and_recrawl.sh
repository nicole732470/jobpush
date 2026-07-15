#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/ops/set_asana_p0.sql"

SITE_ID="$("${PSQL[@]}" -qAt -c "
  SELECT site_id
  FROM jobpush.career_sites
  WHERE consolidation_key='26-3912448'
    AND site_url='https://asana.com/jobs/all'
    AND source_type='greenhouse'
    AND verification_status='verified'
    AND crawl_enabled
  ORDER BY site_id DESC
  LIMIT 1;
")"

if [[ -z "$SITE_ID" ]]; then
  echo "Asana career site not found after P0 setup" >&2
  exit 1
fi

"${PSQL[@]}" -q -c "
  UPDATE jobpush.career_sites
  SET next_crawl_at=now(), crawl_status='pending', last_error=NULL, updated_at=now()
  WHERE site_id=$SITE_ID;
"

# Bypass nightly due-cutoff freeze for an immediate manual recrawl.
echo "Re-crawling Asana site_id=$SITE_ID via greenhouse pilot"
export CONSOLIDATION_KEY="26-3912448" SOURCE_TYPE="greenhouse" SITE_ID="$SITE_ID"
export ADAPTER_NAME="greenhouse-api" ADAPTER_VERSION="0.2.0"
export ADAPTER_SCRIPT="scripts/crawl_greenhouse.py"
export COHORT="asana-manual-recrawl" PRIORITY_TIER="P0"
export SCOPE_METHOD="local_filter"
bash "$SCRIPT_DIR/lib/run_structured_adapter_pilot.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/ops/asana_status.sql"

"${PSQL[@]}" -P pager=off -c "
SELECT count(*) FILTER (WHERE active AND market_scope='US') AS active_us_jobs,
       count(*) FILTER (WHERE active) AS active_jobs,
       max(last_seen_at) AS last_seen_at
FROM jobpush.job_postings
WHERE site_id=$SITE_ID;

SELECT run_id, status, raw_job_count, parsed_job_count, new_job_count,
       updated_job_count, closed_job_count, finished_at
FROM jobpush.crawl_runs
WHERE site_id=$SITE_ID
ORDER BY run_id DESC
LIMIT 3;
"
