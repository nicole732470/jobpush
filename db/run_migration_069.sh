#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/069_company_tavily_enrichment.sql"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -P pager=off -c "
SELECT
    count(*) FILTER (WHERE tavily_searched) AS searched_companies,
    count(*) FILTER (WHERE retained_candidate_count > 0) AS with_candidates,
    count(*) FILTER (WHERE structured_ats_candidate_count > 0) AS with_structured_ats,
    count(*) FILTER (WHERE has_successful_crawl) AS with_successful_crawl
FROM jobpush.company_tavily_discovery_features;
"
