#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/LCA_Disclosure_Data_FY2025_Q1.xlsx" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REGION="us-east-2"
SOURCE_XLSX="$1"
PATCH_CSV="$(mktemp -t fy2025-q1-wages.XXXXXX.csv)"
trap 'rm -f "$PATCH_CSV"' EXIT

python3 "$REPO_DIR/scripts/extract_lca_wage_patch.py" "$SOURCE_XLSX" "$PATCH_CSV"

RDS_HOST="${RDS_HOST:-$(aws rds describe-db-instances \
  --region "$REGION" --db-instance-identifier joblens-db \
  --query 'DBInstances[0].Endpoint.Address' --output text)}"
RDS_PORT="${RDS_PORT:-5432}"
RDS_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id joblens/rds --region "$REGION" --query SecretString --output text)
RDS_USER=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["username"])' "$RDS_SECRET")
RDS_PASS=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["password"])' "$RDS_SECRET")
RDS_DB=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["database"])' "$RDS_SECRET")
unset RDS_SECRET

export PGPASSWORD="$RDS_PASS"
export PGSSLMODE=require
PSQL=(psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1)

"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/018_repair_fy2025_q1_wages.sql"
"${PSQL[@]}" -c "\\copy jobpush.lca_wage_repair_stage FROM '$PATCH_CSV' WITH (FORMAT csv, HEADER true)"
"${PSQL[@]}" -f "$SCRIPT_DIR/repair/repair_lca_wages_fy2025_q1.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/refresh_employer_filing_stats.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT salary_score, COUNT(*) AS companies
   FROM jobpush.company_targets_consolidated
   GROUP BY salary_score ORDER BY salary_score DESC;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(*) AS remaining_target_companies_without_valid_salary
   FROM jobpush.company_targets_consolidated
   WHERE target_role_score = 1
     AND target_role_valid_salary_lca_count = 0;"
