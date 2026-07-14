#!/usr/bin/env bash
# Replace stale Greenhouse/Ashby/Lever boards with a newly discovered rank-1 ATS board.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${1:-25}"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "limit must be positive" >&2; exit 2; }
RUN_ID="ats-404-recovery-$(date -u +%Y%m%dT%H%M%SZ)-$$"
COHORT="daily-ats-404-recovery"
WORK_DIR="$(mktemp -d -t jobpush-ats-recovery.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
TARGETS="$WORK_DIR/targets.csv"
CANDIDATES="$WORK_DIR/candidates.csv"
RESULTS="$WORK_DIR/results.csv"

"${PSQL[@]}" -c "\copy (
  SELECT target.consolidation_key,target.canonical_name,target.priority_tier,target.priority_score,
         array_to_string(COALESCE(identity.tavily_search_terms,ARRAY[target.canonical_name]),'|') AS search_terms
  FROM jobpush.crawl_targets target
  LEFT JOIN jobpush.company_identity_search identity USING(consolidation_key)
  WHERE target.enabled
    AND EXISTS (
      SELECT 1 FROM jobpush.career_sites site
      WHERE site.consolidation_key=target.consolidation_key
        AND site.source_type IN ('greenhouse','ashby','lever')
        AND coalesce(site.last_error,'') ~* '404'
    )
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites healthy
      WHERE healthy.consolidation_key=target.consolidation_key
        AND healthy.verification_status='verified' AND healthy.crawl_enabled
        AND healthy.crawl_status<>'failed'
    )
  ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 ELSE 3 END,
           target.priority_score DESC NULLS LAST,target.canonical_name
  LIMIT $LIMIT
) TO '$TARGETS' WITH (FORMAT csv,HEADER true)"

COUNT=$(( $(wc -l < "$TARGETS") - 1 ))
(( COUNT > 0 )) || { echo "No stale ATS boards need rediscovery."; exit 0; }

APP_SECRET="$(aws secretsmanager get-secret-value --secret-id joblens/app --region us-east-2 --query SecretString --output text)"
TAVILY_API_KEY="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("TAVILY_API_KEY", ""))' "$APP_SECRET")"
unset APP_SECRET
[[ -n "$TAVILY_API_KEY" ]] || { echo "TAVILY_API_KEY is not configured" >&2; exit 1; }
export TAVILY_API_KEY
python3 "$REPO_DIR/scripts/discover_career_sites.py" "$TARGETS" "$CANDIDATES" "$RESULTS" \
  --run-id "$RUN_ID" --workers "${TAVILY_WORKERS:-1}"
unset TAVILY_API_KEY

"${PSQL[@]}" -c "\copy jobpush.career_site_discovery_stage FROM '$CANDIDATES' WITH (FORMAT csv,HEADER true)"
"${PSQL[@]}" -c "\copy jobpush.career_site_discovery_result_stage FROM '$RESULTS' WITH (FORMAT csv,HEADER true)"
"${PSQL[@]}" -v run_id="$RUN_ID" -v cohort="$COHORT" -f "$SCRIPT_DIR/load/finalize_career_site_discovery.sql"

"${PSQL[@]}" -v run_id="$RUN_ID" -v ON_ERROR_STOP=1 <<'SQL'
WITH recovered_targets AS (
  SELECT DISTINCT consolidation_key
  FROM jobpush.career_site_discovery_attempts
  WHERE run_id=:'run_id' AND search_succeeded AND candidate_count>0
), ranked AS (
  SELECT site.site_id,site.consolidation_key,
         row_number() OVER(PARTITION BY site.consolidation_key ORDER BY site.candidate_rank,site.candidate_score DESC,site.site_id) rn
  FROM jobpush.career_sites site JOIN recovered_targets USING(consolidation_key)
  WHERE site.source_type IN ('greenhouse','ashby','lever')
    AND site.verification_status='unverified'
    AND coalesce(site.last_error,'') !~* '404'
    AND site.last_discovered_at>=now()-interval '1 hour'
), activated AS (
  UPDATE jobpush.career_sites site
  SET verification_status='verified',crawl_enabled=TRUE,crawl_status='pending',next_crawl_at=now(),
      target_country_code='US',scope_method='local_filter',reviewed_at=now(),
      reviewed_by='system:ats-404-auto-rediscovery-v1',
      review_notes=concat_ws('; ',site.review_notes,'Auto-activated replacement for stale 404 ATS board'),updated_at=now()
  FROM ranked WHERE site.site_id=ranked.site_id AND ranked.rn=1
  RETURNING site.consolidation_key,site.site_id
)
UPDATE jobpush.career_sites stale
SET verification_status='rejected',crawl_enabled=FALSE,crawl_status='paused',next_crawl_at=NULL,
    reviewed_at=now(),reviewed_by='system:ats-404-auto-rediscovery-v1',
    review_notes=concat_ws('; ',stale.review_notes,'Replaced by auto-rediscovered ATS board'),updated_at=now()
FROM activated
WHERE stale.consolidation_key=activated.consolidation_key
  AND stale.site_id<>activated.site_id
  AND stale.source_type IN ('greenhouse','ashby','lever')
  AND coalesce(stale.last_error,'') ~* '404';
SQL

echo "ATS 404 rediscovery completed: targets=$COUNT run_id=$RUN_ID"
