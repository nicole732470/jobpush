#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${ENRICHMENT_LIMIT:-20}"
: "${APP_SECRET_ID:=joblens/app}"
: "${REGION:=us-east-2}"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "ENRICHMENT_LIMIT must be positive" >&2; exit 2; }

TMP_DIR="$(mktemp -d -t jobpush-tavily-enrichment.XXXXXX)"
trap 'rm -rf "$TMP_DIR"; unset TAVILY_API_KEY' EXIT
INPUT_CSV="$TMP_DIR/companies.csv"
OUTPUT_SQL="$TMP_DIR/enrichment.sql"

SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$APP_SECRET_ID" --region "$REGION" \
  --query SecretString --output text)
export TAVILY_API_KEY="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("TAVILY_API_KEY", ""))' "$SECRET")"
unset SECRET
[[ -n "$TAVILY_API_KEY" ]] || { echo "TAVILY_API_KEY missing from secret" >&2; exit 1; }

"${PSQL[@]}" -qAt -c "COPY (
    SELECT target.consolidation_key, target.canonical_name
    FROM jobpush.company_targets_consolidated target
    JOIN jobpush.company_tavily_discovery_features feature USING (consolidation_key)
    LEFT JOIN jobpush.company_external_enrichment enrichment USING (consolidation_key)
    WHERE feature.tavily_searched
      AND target.crawl_priority_tier IN ('P0', 'P1')
      AND enrichment.consolidation_key IS NULL
    ORDER BY target.crawl_priority_tier, target.priority_score DESC,
             md5(target.consolidation_key || 'tavily-enrichment-pilot-v1')
    LIMIT $LIMIT
) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > "$INPUT_CSV"

python3 "$REPO_DIR/scripts/enrich_companies_tavily.py" "$INPUT_CSV" "$OUTPUT_SQL"
unset TAVILY_API_KEY
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$OUTPUT_SQL"

"${PSQL[@]}" -P pager=off -c "
SELECT target.canonical_name, enrichment.company_description,
       cardinality(enrichment.source_urls) AS source_count,
       enrichment.researched_at
FROM jobpush.company_external_enrichment enrichment
JOIN jobpush.company_targets_consolidated target USING (consolidation_key)
ORDER BY enrichment.researched_at DESC
LIMIT $LIMIT;
"
