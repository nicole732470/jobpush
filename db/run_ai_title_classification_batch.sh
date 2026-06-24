#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${1:-50}"
BATCH_SIZE="${2:-10}"
APPLY_LIMIT="${3:-500}"
: "${APP_SECRET_ID:=joblens/app}"
: "${REGION:=us-east-2}"

[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "limit must be a positive integer" >&2; exit 2; }
[[ "$BATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || { echo "batch size must be a positive integer" >&2; exit 2; }
[[ "$APPLY_LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "apply limit must be a positive integer" >&2; exit 2; }

APP_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$APP_SECRET_ID" \
  --region "$REGION" \
  --query SecretString \
  --output text)
export LLM_API_KEY="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("LLM_API_KEY", ""))' "$APP_SECRET")"
export LLM_BASE_URL="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("LLM_BASE_URL", "https://api.openai.com/v1"))' "$APP_SECRET")"
export LLM_MODEL="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("LLM_MODEL", "gpt-4.1-mini"))' "$APP_SECRET")"
unset APP_SECRET

if [[ "$LLM_MODEL" == *":free"* && "$LIMIT" -gt 50 ]]; then
  echo "LLM_MODEL=$LLM_MODEL is a free/rate-limited model; capping batch from $LIMIT to 50." >&2
  LIMIT=50
fi

TMP_DIR="$(mktemp -d -t jobpush-ai-title.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
INPUT_CSV="$TMP_DIR/review_titles.csv"
OUTPUT_SQL="$TMP_DIR/ai_title_inserts.sql"

"${PSQL[@]}" -qAt -c "COPY (
    WITH distinct_companies AS (
        SELECT DISTINCT posting.normalized_title, target.canonical_name
        FROM jobpush.job_postings posting
        JOIN jobpush.crawl_targets target USING (consolidation_key)
        WHERE posting.active AND posting.market_scope = 'US'
    ), ranked AS (
        SELECT normalized_title, canonical_name,
               row_number() OVER (PARTITION BY normalized_title ORDER BY canonical_name) AS company_rank
        FROM distinct_companies
    ), examples AS (
        SELECT normalized_title,
               string_agg(canonical_name, ' | ' ORDER BY canonical_name) AS example_companies
        FROM ranked
        WHERE company_rank <= 3
        GROUP BY normalized_title
    )
    SELECT queue.normalized_title, queue.example_title,
           queue.active_posting_count, queue.company_count,
           COALESCE(examples.example_companies, '') AS example_companies,
           queue.suggestion_reason,
           COALESCE(queue.matched_soc_titles, '') AS matched_soc_titles
    FROM jobpush.job_title_review_queue queue
    LEFT JOIN examples USING (normalized_title)
    ORDER BY queue.active_posting_count DESC, queue.company_count DESC, queue.normalized_title
    LIMIT $LIMIT
) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > "$INPUT_CSV"

python3 "$REPO_DIR/scripts/classify_job_titles_ai.py" \
  --input "$INPUT_CSV" \
  --output-sql "$OUTPUT_SQL" \
  --limit "$LIMIT" \
  --batch-size "$BATCH_SIZE"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$OUTPUT_SQL"
"${PSQL[@]}" -P pager=off -c \
  "SELECT * FROM jobpush.apply_ai_job_title_classifications(0.88, 0.84, $APPLY_LIMIT);"
"${PSQL[@]}" -P pager=off -c \
  "SELECT classification_status, rule_version, count(*) AS titles
   FROM jobpush.job_title_labels
   GROUP BY 1,2
   ORDER BY 1,2;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT role_status, count(*) AS active_us_jobs
   FROM jobpush.dashboard_jobs
   GROUP BY 1
   ORDER BY 1;"
