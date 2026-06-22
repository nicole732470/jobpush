#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="us-east-2"

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
  -f "$SCRIPT_DIR/migrations/014_product_manager_score.sql"
psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/refresh/refresh_company_targets.sql"
