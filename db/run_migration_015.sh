#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="us-east-2"
EMPLOYERS_CSV="/tmp/jobpush-load/linkedin_top_employers_2026.csv"
MATCH_TERMS_CSV="/tmp/jobpush-load/linkedin_top_employer_match_terms.csv"

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
  -f "$SCRIPT_DIR/migrations/015_linkedin_top_employer_score.sql"

mkdir -p /tmp/jobpush-load
cp "$SCRIPT_DIR/../config/linkedin_top_employers_2026.csv" "$EMPLOYERS_CSV"
cp "$SCRIPT_DIR/../config/linkedin_top_employer_match_terms.csv" "$MATCH_TERMS_CSV"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/load/load_linkedin_top_employers.sql"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -c "\\copy jobpush.linkedin_top_employers_2026 (employer_key, linkedin_name, best_rank, appearance_count, regions, source_url, source_year, notes) FROM '${EMPLOYERS_CSV}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -c "\\copy jobpush.linkedin_top_employer_match_terms (employer_key, linkedin_name, match_key, match_kind, term_source) FROM '${MATCH_TERMS_CSV}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/refresh/rebuild_linkedin_top_employer_matches.sql"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/refresh/refresh_company_targets.sql"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -P pager=off -c \
  "SELECT COUNT(*) AS employers FROM jobpush.linkedin_top_employers_2026;"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -P pager=off -c \
  "SELECT COUNT(DISTINCT fein) AS matched_companies FROM jobpush.linkedin_top_employer_company_matches;"

psql -h "$RDS_HOST" -U "$RDS_USER" -d "$RDS_DB" -P pager=off -c \
  "SELECT linkedin_top_employer_score, COUNT(*) FROM jobpush.company_targets GROUP BY 1 ORDER BY 1;"
