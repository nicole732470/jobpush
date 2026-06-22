#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="us-east-2"
CSV_PATH="/tmp/jobpush-load/soc_role_title_mappings.csv"

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
  -f "$SCRIPT_DIR/migrations/007_soc_role_title_mappings.sql"

mkdir -p /tmp/jobpush-load
cp "$SCRIPT_DIR/../config/soc_role_title_mappings.csv" "$CSV_PATH"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/load/load_soc_role_title_mappings.sql"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -c "\\copy jobpush.soc_role_title_mappings (raw_job_title, normalized_soc_code, soc_title, soc_lca_count, raw_lca_count, normalized_job_title) FROM '${CSV_PATH}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -P pager=off -c \
  "SELECT COUNT(*) AS mapping_rows FROM jobpush.soc_role_title_mappings;"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -P pager=off -c \
  "SELECT raw_job_title, normalized_job_title, soc_title, raw_lca_count
   FROM jobpush.soc_role_title_mappings
   ORDER BY raw_lca_count DESC
   LIMIT 5;"
