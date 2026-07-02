#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${1:-150}"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "LIMIT must be a positive integer" >&2; exit 2; }

RUN_ID="career-expansion-$(date -u +%Y%m%dT%H%M%SZ)-$$"
COHORT="effective-tier-p0-p1-p2-p3-expansion"
WORK_DIR="$(mktemp -d -t jobpush-career-expansion.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
TARGETS="$WORK_DIR/targets.csv"
CANDIDATES="$WORK_DIR/candidates.csv"
RESULTS="$WORK_DIR/results.csv"

# Normal Tavily expansion is credit-conservative: spend one basic-search credit
# only on companies that have never been searched. Historical retry/not_found
# rows require a dedicated recovery reset after confirming the failure was
# provider/network-wide.
"${PSQL[@]}" -c "\copy (
  SELECT target.consolidation_key, target.canonical_name, target.priority_tier, target.priority_score
       , array_to_string(COALESCE(identity.tavily_search_terms, ARRAY[target.canonical_name]), '|') AS search_terms
  FROM jobpush.crawl_targets target
  LEFT JOIN jobpush.company_identity_search identity USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P0','P1','P2','P3')
    AND target.last_discovery_at IS NULL
    AND target.discovery_status = 'pending'
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
  "$TARGETS" "$CANDIDATES" "$RESULTS" --run-id "$RUN_ID" \
  --workers "${TAVILY_WORKERS:-1}"
unset TAVILY_API_KEY

"${PSQL[@]}" -c "\copy jobpush.career_site_discovery_stage FROM '$CANDIDATES' WITH (FORMAT csv, HEADER true)"
"${PSQL[@]}" -c "\copy jobpush.career_site_discovery_result_stage FROM '$RESULTS' WITH (FORMAT csv, HEADER true)"
"${PSQL[@]}" -v run_id="$RUN_ID" -v cohort="$COHORT" \
  -f "$SCRIPT_DIR/load/finalize_career_site_discovery.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT run_id,cohort,target_count,candidate_count,error_count,estimated_credits,status
   FROM jobpush.career_site_discovery_runs WHERE run_id='$RUN_ID';
   SELECT priority_tier,action_status,count(*) AS companies
   FROM jobpush.career_site_review_workbench
   GROUP BY priority_tier,action_status ORDER BY priority_tier,action_status;"
