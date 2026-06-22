#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${1:-103}"
MIN_SCORE="${2:-4.5}"
if [[ ! "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -le 0 ]]; then
  echo "LIMIT must be a positive integer" >&2
  exit 2
fi
if [[ ! "$MIN_SCORE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "MIN_SCORE must be numeric" >&2
  exit 2
fi
RUN_ID="career-pilot-$(date -u +%Y%m%dT%H%M%SZ)-$$"
COHORT="priority-score-${MIN_SCORE}-plus"
WORK_DIR="$(mktemp -d -t jobpush-career-discovery.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
TARGETS="$WORK_DIR/targets.csv"
CANDIDATES="$WORK_DIR/candidates.csv"
RESULTS="$WORK_DIR/results.csv"

"${PSQL[@]}" -c "\\copy (
  SELECT consolidation_key, canonical_name, priority_tier, priority_score
  FROM jobpush.crawl_targets
  WHERE enabled
    AND priority_score >= ${MIN_SCORE}::NUMERIC
    AND discovery_status IN ('pending', 'retry', 'not_found')
  ORDER BY priority_score DESC, canonical_name
  LIMIT ${LIMIT}
) TO '$TARGETS' WITH (FORMAT csv, HEADER true)"

TARGET_COUNT=$(( $(wc -l < "$TARGETS") - 1 ))
if [[ "$TARGET_COUNT" -le 0 ]]; then
  echo "No eligible targets found."
  exit 0
fi

APP_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id joblens/app --region us-east-2 --query SecretString --output text)
TAVILY_API_KEY=$(python3 -c \
  'import json,sys; print(json.loads(sys.argv[1]).get("TAVILY_API_KEY", ""))' \
  "$APP_SECRET")
unset APP_SECRET
if [[ -z "$TAVILY_API_KEY" ]]; then
  echo "TAVILY_API_KEY is not configured in joblens/app" >&2
  exit 1
fi
export TAVILY_API_KEY

python3 "$REPO_DIR/scripts/discover_career_sites.py" \
  "$TARGETS" "$CANDIDATES" "$RESULTS" --run-id "$RUN_ID"
unset TAVILY_API_KEY

"${PSQL[@]}" -c "\\copy jobpush.career_site_discovery_stage FROM '$CANDIDATES' WITH (FORMAT csv, HEADER true)"
"${PSQL[@]}" -c "\\copy jobpush.career_site_discovery_result_stage FROM '$RESULTS' WITH (FORMAT csv, HEADER true)"
"${PSQL[@]}" -v run_id="$RUN_ID" -v cohort="$COHORT" \
  -f "$SCRIPT_DIR/load/finalize_career_site_discovery.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT run_id, cohort, target_count, candidate_count, error_count,
          estimated_credits, status
   FROM jobpush.career_site_discovery_runs
   WHERE run_id = '$RUN_ID';"

"${PSQL[@]}" -P pager=off -c \
  "SELECT source_type, COUNT(*) AS candidates
   FROM jobpush.career_sites
   WHERE verification_status = 'unverified'
     AND consolidation_key IN (
       SELECT consolidation_key FROM jobpush.crawl_targets
       WHERE priority_score >= ${MIN_SCORE}::NUMERIC
     )
   GROUP BY source_type ORDER BY candidates DESC;"
