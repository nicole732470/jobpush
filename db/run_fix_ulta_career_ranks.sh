#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off -f "$SCRIPT_DIR/manual/fix_ulta_career_ranks.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, candidate_rank, site_url, verification_status
   FROM jobpush.career_sites WHERE consolidation_key = 'ulta' ORDER BY candidate_rank;"
