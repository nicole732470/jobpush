#!/usr/bin/env bash
# Shared RDS connection for JobPush refresh/migration scripts.
# Source this file, then use "${PSQL[@]}" for commands.

if [[ -z "${AWS_PROFILE:-}" ]] \
    && { [[ -f "${AWS_CONFIG_FILE:-${HOME:-}/.aws/config}" ]] \
         || [[ -f "${AWS_SHARED_CREDENTIALS_FILE:-${HOME:-}/.aws/credentials}" ]]; } \
    && command -v aws >/dev/null \
    && aws configure list-profiles 2>/dev/null | grep -qx 'jobpush-new'; then
  export AWS_PROFILE=jobpush-new
fi

: "${REGION:=us-east-2}"
: "${RDS_INSTANCE_ID:=joblens-db}"
: "${RDS_SECRET_ID:=joblens/rds}"
: "${RDS_PASS:=${PGPASSWORD:-}}"

if [[ -z "${RDS_HOST:-}" ]]; then
  RDS_HOST=$(aws rds describe-db-instances \
    --region "$REGION" \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)
fi

: "${RDS_PORT:=5432}"

if [[ -z "${RDS_USER:-}" || -z "${RDS_PASS:-}" || -z "${RDS_DB:-}" ]]; then
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
fi

export PGPASSWORD="$RDS_PASS"
export PGSSLMODE=require
export RDS_HOST RDS_PORT RDS_USER RDS_DB PGPASSWORD PGSSLMODE

PSQL=(psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1)
