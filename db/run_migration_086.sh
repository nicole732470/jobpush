#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/086_generic_html_domain_cleanup_20260627.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT source_type, verification_status, count(*) AS sites
   FROM jobpush.career_sites
   WHERE discovery_source IN ('tavily_basic','generic_html_link_resolver')
   GROUP BY 1,2
   ORDER BY 1,2;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT discovery_status, count(*) AS companies
   FROM jobpush.crawl_targets
   WHERE enabled AND priority_tier IN ('P0','P1')
   GROUP BY 1
   ORDER BY 1;"
