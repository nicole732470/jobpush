#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="us-east-2"
LOAD_DIR="/tmp/jobpush-load"

RDS_HOST=$(aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier joblens-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

RDS_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id joblens/rds \
  --region "$REGION" \
  --query SecretString \
  --output text)

RDS_USER=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["username"])' "$RDS_SECRET")
RDS_PASS=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["password"])' "$RDS_SECRET")
RDS_DB=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["database"])' "$RDS_SECRET")
unset RDS_SECRET

export PGPASSWORD="$RDS_PASS"
export PGSSLMODE=require

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/016_company_consolidation.sql"

mkdir -p "$LOAD_DIR"
cp "$SCRIPT_DIR/../config/company_consolidation_policies.csv" "$LOAD_DIR/"
cp "$SCRIPT_DIR/../config/company_consolidation_name_denies.csv" "$LOAD_DIR/"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/load/load_company_consolidation_config.sql"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -c "\\copy jobpush.company_consolidation_policies (employer_key, linkedin_name, policy, min_feins, name_allow_regex, name_deny_regex, notes) FROM '${LOAD_DIR}/company_consolidation_policies.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -c "\\copy jobpush.company_consolidation_name_denies (deny_pattern, notes) FROM '${LOAD_DIR}/company_consolidation_name_denies.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/refresh/rebuild_company_consolidation_members.sql"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -P pager=off -c \
  "SELECT COUNT(*) AS merged_groups FROM jobpush.company_consolidation_groups;"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -P pager=off -c \
  "SELECT COUNT(*) AS merged_feins FROM jobpush.company_consolidation_members;"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -P pager=off -c \
  "SELECT COUNT(*) AS consolidated_rows,
          COUNT(*) FILTER (WHERE is_merged_group) AS merged_rows,
          COUNT(*) FILTER (WHERE NOT is_merged_group) AS singleton_rows
   FROM jobpush.company_targets_consolidated;"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -P pager=off -c \
  "SELECT canonical_name, member_fein_count, lca_count, priority_score
   FROM jobpush.company_targets_consolidated
   WHERE is_merged_group
   ORDER BY lca_count DESC
   LIMIT 12;"
