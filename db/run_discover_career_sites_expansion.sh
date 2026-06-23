#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${1:-150}"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "LIMIT must be a positive integer" >&2; exit 2; }

RUN_ID="career-expansion-$(date -u +%Y%m%dT%H%M%SZ)-$$"
COHORT="effective-tier-p0-p1-p2-expansion"
WORK_DIR="$(mktemp -d -t jobpush-career-expansion.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
TARGETS="$WORK_DIR/targets.csv"
CANDIDATES="$WORK_DIR/candidates.csv"
RESULTS="$WORK_DIR/results.csv"

"${PSQL[@]}" -c "\copy (
  SELECT consolidation_key, canonical_name, priority_tier, priority_score
  FROM jobpush.crawl_targets target
  WHERE target.enabled
    AND target.priority_tier IN ('P0','P1','P2')
    AND target.last_discovery_at IS NULL
    AND target.discovery_status IN ('pending','retry','not_found')
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites site
      WHERE site.consolidation_key=target.consolidation_key
        AND site.verification_status IN ('verified','unverified')
    )
  ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
           target.priority_score DESC, target.canonical_name
  LIMIT $LIMIT
) TO '$TARGETS' WITH (FORMAT csv, HEADER true)"

TARGET_COUNT=$(( $(wc -l < "$TARGETS") - 1 ))
if [[ "$TARGET_COUNT" -le 0 ]]; then
  echo "No never-searched P-tier targets found."
  exit 0
fi
echo "Searching $TARGET_COUNT companies; expected basic-search credits: $TARGET_COUNT"

APP_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id joblens/app --region us-east-2 --query SecretString --output text)
TAVILY_API_KEY=$(python3 -c \
  'import json,sys; print(json.loads(sys.argv[1]).get("TAVILY_API_KEY", ""))' \
  "$APP_SECRET")
unset APP_SECRET
[[ -n "$TAVILY_API_KEY" ]] || { echo "TAVILY_API_KEY is not configured" >&2; exit 1; }
export TAVILY_API_KEY

python3 "$REPO_DIR/scripts/discover_career_sites.py" \
  "$TARGETS" "$CANDIDATES" "$RESULTS" --run-id "$RUN_ID"
unset TAVILY_API_KEY

"${PSQL[@]}" -c "\copy jobpush.career_site_discovery_stage FROM '$CANDIDATES' WITH (FORMAT csv, HEADER true)"
"${PSQL[@]}" -c "\copy jobpush.career_site_discovery_result_stage FROM '$RESULTS' WITH (FORMAT csv, HEADER true)"
"${PSQL[@]}" -v run_id="$RUN_ID" -v cohort="$COHORT" \
  -f "$SCRIPT_DIR/load/finalize_career_site_discovery.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT run_id,cohort,target_count,candidate_count,error_count,estimated_credits,status
   FROM jobpush.career_site_discovery_runs WHERE run_id='$RUN_ID';
   SELECT priority_tier,count(*) AS companies
   FROM jobpush.career_site_company_review_queue_ranked
   GROUP BY priority_tier ORDER BY priority_tier;"
