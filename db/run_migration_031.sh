#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 031 Ulta consolidation policy + manual FEIN matches"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/031_ulta_consolidation.sql"

echo "==> rebuild consolidation members"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/rebuild_company_consolidation_members.sql"

echo "==> refresh consolidated scores"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"

echo "==> sync crawl targets"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"

echo "==> migrate Ulta career sites to merged key"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/031_ulta_career_sites.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, canonical_name, is_merged_group, member_fein_count,
          lca_count, target_role_lca_count, priority_score, crawl_priority_tier
   FROM jobpush.company_targets_consolidated
   WHERE consolidation_key = 'ulta';"

"${PSQL[@]}" -P pager=off -c \
  "SELECT fein, company_name FROM jobpush.company_consolidation_members
   WHERE group_id = 'ulta' ORDER BY lca_count DESC;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT * FROM jobpush.career_site_company_review_queue
   WHERE consolidation_key = 'ulta';"

"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, candidate_rank, site_url, verification_status
   FROM jobpush.career_sites
   WHERE consolidation_key = 'ulta'
   ORDER BY candidate_rank;"
