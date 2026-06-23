#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${1:-50}"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "LIMIT must be a positive integer" >&2; exit 2; }

RUN_ID="potential-p0-sample-$(date -u +%Y%m%dT%H%M%SZ)-$$"
COHORT="potential-p0-stratified-random"
WORK_DIR="$(mktemp -d -t jobpush-potential-p0.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
TARGETS="$WORK_DIR/targets.csv"
CANDIDATES="$WORK_DIR/candidates.csv"
RESULTS="$WORK_DIR/results.csv"

"${PSQL[@]}" -c "\copy (
  WITH eligible AS (
    SELECT target.consolidation_key,target.canonical_name,target.priority_tier,target.priority_score,
           consolidated.chicago_score,consolidated.linkedin_top_employer_score,
           consolidated.lca_count,
           CASE
             WHEN consolidated.chicago_score>0 AND consolidated.linkedin_top_employer_score>0
               THEN 'chicago_and_linkedin'
             WHEN consolidated.chicago_score>0 THEN 'chicago'
             WHEN consolidated.linkedin_top_employer_score>0 THEN 'linkedin_top_employer'
             WHEN consolidated.lca_count>=100 THEN 'large_lca_sponsor'
             ELSE 'diverse_random'
           END AS sample_bucket
    FROM jobpush.crawl_targets target
    JOIN jobpush.company_targets_consolidated consolidated USING(consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P1','P2')
      AND target.last_discovery_at IS NULL
      AND target.discovery_status IN ('pending','retry','not_found')
      AND NOT EXISTS (
        SELECT 1 FROM jobpush.career_sites site
        WHERE site.consolidation_key=target.consolidation_key
          AND site.verification_status IN ('verified','unverified')
      )
  ), ranked AS (
    SELECT eligible.*,
           row_number() OVER (
             PARTITION BY sample_bucket
             ORDER BY priority_score DESC,
                      md5(consolidation_key || current_date::text)
           ) AS bucket_rank
    FROM eligible
  ), quota_selected AS (
    SELECT * FROM ranked
    WHERE bucket_rank <= CASE sample_bucket
      WHEN 'chicago_and_linkedin' THEN 10
      WHEN 'chicago' THEN 15
      WHEN 'linkedin_top_employer' THEN 10
      WHEN 'large_lca_sponsor' THEN 10
      ELSE 5 END
    ORDER BY md5(consolidation_key || 'quota')
    LIMIT $LIMIT
  ), fill AS (
    SELECT ranked.* FROM ranked
    WHERE NOT EXISTS (
      SELECT 1 FROM quota_selected selected
      WHERE selected.consolidation_key=ranked.consolidation_key
    )
    ORDER BY md5(consolidation_key || current_date::text || 'fill')
    LIMIT (SELECT GREATEST(0,$LIMIT-count(*)) FROM quota_selected)
  ), final_sample AS (
    SELECT * FROM quota_selected
    UNION ALL
    SELECT * FROM fill
  )
  SELECT consolidation_key,canonical_name,priority_tier,priority_score
  FROM final_sample
  ORDER BY md5(consolidation_key || 'final')
) TO '$TARGETS' WITH (FORMAT csv, HEADER true)"

TARGET_COUNT=$(( $(wc -l < "$TARGETS") - 1 ))
[[ "$TARGET_COUNT" -gt 0 ]] || { echo "No eligible potential-P0 targets found."; exit 0; }
echo "Searching $TARGET_COUNT stratified potential-P0 companies; expected credits: $TARGET_COUNT"

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
  "SELECT run_id,target_count,candidate_count,error_count,estimated_credits,status
   FROM jobpush.career_site_discovery_runs WHERE run_id='$RUN_ID';
   SELECT potential_p0_signal,count(*) AS companies
   FROM jobpush.career_site_review_workbench
   WHERE action_status='REVIEW_CANDIDATES'
   GROUP BY potential_p0_signal ORDER BY companies DESC;"
