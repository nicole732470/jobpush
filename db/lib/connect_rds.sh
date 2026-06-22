#!/usr/bin/env bash
# Shared RDS connection for JobPush refresh/migration scripts.
# Source this file, then use "${PSQL[@]}" for commands.

: "${REGION:=us-east-2}"
: "${RDS_INSTANCE_ID:=joblens-db}"
: "${RDS_SECRET_ID:=joblens/rds}"

if [[ -z "${RDS_HOST:-}" ]]; then
  RDS_HOST=$(aws rds describe-db-instances \
    --region "$REGION" \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)
fi

: "${RDS_PORT:=5432}"

if [[ -z "${RDS_SECRET:-}" ]]; then
  RDS_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "$RDS_SECRET_ID" \
    --region "$REGION" \
    --query SecretString \
    --output text)
fi

RDS_USER=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["username"])' "$RDS_SECRET")
RDS_PASS=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["password"])' "$RDS_SECRET")
RDS_DB=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["database"])' "$RDS_SECRET")
unset RDS_SECRET

export PGPASSWORD="$RDS_PASS"
export PGSSLMODE=require

PSQL=(psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1)
