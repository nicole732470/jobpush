#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 021 linkedin match confidence"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/021_linkedin_match_confidence.sql"

echo "==> load scoring excludes"
"${PSQL[@]}" -f "$SCRIPT_DIR/load/load_linkedin_scoring_excludes.sql"

echo "==> rebuild linkedin company matches"
/usr/bin/time -p "${PSQL[@]}" -c '\timing on' \
  -f "$SCRIPT_DIR/refresh/rebuild_linkedin_top_employer_matches.sql"

echo "==> refresh consolidated scores"
/usr/bin/time -p "${PSQL[@]}" -c '\timing on' \
  -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(DISTINCT fein) AS matched_feins
   FROM jobpush.linkedin_top_employer_company_matches;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT linkedin_top_employer_score, COUNT(*) AS companies
   FROM jobpush.company_targets_consolidated
   WHERE target_role_score = 1
   GROUP BY linkedin_top_employer_score
   ORDER BY linkedin_top_employer_score DESC;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT canonical_name, priority_score, linkedin_top_employer_score
   FROM jobpush.company_targets_consolidated
   WHERE canonical_name ILIKE '%abstract%security%';"

"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(*) AS abstract_matches
   FROM jobpush.linkedin_top_employer_company_matches
   WHERE employer_key = 'abstract';"
