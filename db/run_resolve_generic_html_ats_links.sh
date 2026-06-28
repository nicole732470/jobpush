#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${GENERIC_RESOLVE_LIMIT:-50}"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "GENERIC_RESOLVE_LIMIT must be a positive integer" >&2; exit 2; }

RUN_ID="generic-ats-resolver-$(date -u +%Y%m%dT%H%M%SZ)-$$"
WORK_DIR="$(mktemp -d -t jobpush-generic-ats.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
TARGETS="$WORK_DIR/targets.csv"
CANDIDATES="$WORK_DIR/candidates.csv"
RESULTS="$WORK_DIR/results.csv"

"${PSQL[@]}" -c "\copy (
  SELECT DISTINCT ON (target.consolidation_key)
      site.site_id,
      site.consolidation_key,
      target.canonical_name,
      target.priority_tier,
      target.priority_score,
      site.site_url,
      site.candidate_score
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P0','P1')
    AND site.source_type = 'generic_html'
    AND site.verification_status = 'unverified'
    AND site.crawl_enabled = FALSE
    AND COALESCE(site.last_error, '') NOT LIKE 'generic_ats_resolution_attempted%'
    AND NOT EXISTS (
        SELECT 1
        FROM jobpush.career_sites structured
        WHERE structured.consolidation_key = site.consolidation_key
          AND structured.source_type <> 'generic_html'
          AND structured.verification_status IN ('verified', 'unverified')
    )
  ORDER BY target.consolidation_key, target.priority_tier, target.priority_score DESC NULLS LAST,
           site.candidate_score DESC NULLS LAST, site.candidate_rank NULLS LAST
  LIMIT $LIMIT
) TO '$TARGETS' WITH (FORMAT csv, HEADER true)"

TARGET_COUNT=$(( $(wc -l < "$TARGETS") - 1 ))
if [[ "$TARGET_COUNT" -le 0 ]]; then
  echo "No generic HTML candidates require ATS-link resolution."
  exit 0
fi
echo "Resolving ATS links from $TARGET_COUNT generic HTML candidates; Tavily credits used: 0"

python3 "$REPO_DIR/scripts/resolve_generic_ats_links.py" \
  "$TARGETS" "$CANDIDATES" "$RESULTS" --run-id "$RUN_ID" --timeout 8 --workers 8

"${PSQL[@]}" -c "\copy jobpush.career_site_discovery_stage FROM '$CANDIDATES' WITH (FORMAT csv, HEADER true)"
"${PSQL[@]}" -c "\copy jobpush.career_site_discovery_result_stage FROM '$RESULTS' WITH (FORMAT csv, HEADER true)"

"${PSQL[@]}" -v run_id="$RUN_ID" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

INSERT INTO jobpush.career_site_discovery_runs (
    run_id, cohort, target_count, search_count, candidate_count,
    error_count, estimated_credits, status, started_at, notes
)
SELECT
    :'run_id',
    'generic-html-ats-link-resolver',
    COUNT(*),
    0,
    COALESCE(SUM(candidate_count), 0),
    COUNT(*) FILTER (WHERE NOT search_succeeded),
    0,
    'running',
    now(),
    'Zero-credit refinement of retained generic_html candidates'
FROM jobpush.career_site_discovery_result_stage
WHERE run_id = :'run_id'
ON CONFLICT (run_id) DO NOTHING;

INSERT INTO jobpush.career_sites (
    consolidation_key, site_url, normalized_domain, site_kind,
    source_type, source_key, discovery_source, verification_status,
    crawl_enabled, crawl_status, candidate_rank, candidate_score,
    search_query, evidence_title, evidence_snippet, last_discovered_at,
    created_at, updated_at
)
SELECT
    stage.consolidation_key,
    stage.site_url,
    stage.normalized_domain,
    stage.site_kind,
    stage.source_type,
    NULLIF(stage.source_key, ''),
    'generic_html_link_resolver',
    'unverified',
    FALSE,
    'pending',
    stage.candidate_rank,
    stage.candidate_score,
    stage.search_query,
    NULLIF(stage.evidence_title, ''),
    NULLIF(stage.evidence_snippet, ''),
    now(),
    now(),
    now()
FROM jobpush.career_site_discovery_stage stage
WHERE stage.run_id = :'run_id'
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    normalized_domain = EXCLUDED.normalized_domain,
    site_kind = EXCLUDED.site_kind,
    source_type = EXCLUDED.source_type,
    source_key = EXCLUDED.source_key,
    discovery_source = EXCLUDED.discovery_source,
    candidate_rank = LEAST(COALESCE(jobpush.career_sites.candidate_rank, EXCLUDED.candidate_rank), EXCLUDED.candidate_rank),
    candidate_score = GREATEST(COALESCE(jobpush.career_sites.candidate_score, 0), EXCLUDED.candidate_score),
    search_query = EXCLUDED.search_query,
    evidence_title = EXCLUDED.evidence_title,
    evidence_snippet = EXCLUDED.evidence_snippet,
    last_discovered_at = now(),
    updated_at = now();

UPDATE jobpush.crawl_targets target
SET
    discovery_status = 'review_pending',
    next_discovery_at = NULL,
    updated_at = now()
WHERE EXISTS (
    SELECT 1
    FROM jobpush.career_site_discovery_stage stage
    WHERE stage.run_id = :'run_id'
      AND stage.consolidation_key = target.consolidation_key
);

UPDATE jobpush.career_sites site
SET
    last_error = 'generic_ats_resolution_attempted: checked retained generic page for structured ATS links',
    updated_at = now()
FROM jobpush.career_site_discovery_result_stage result
WHERE result.run_id = :'run_id'
  AND result.consolidation_key = site.consolidation_key
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE;

UPDATE jobpush.career_site_discovery_runs
SET status = 'completed', finished_at = now()
WHERE run_id = :'run_id';

DELETE FROM jobpush.career_site_discovery_stage WHERE run_id = :'run_id';
DELETE FROM jobpush.career_site_discovery_result_stage WHERE run_id = :'run_id';

COMMIT;
SQL

"${PSQL[@]}" -P pager=off -c "
SELECT run_id, cohort, target_count, search_count, candidate_count, error_count, estimated_credits, status
FROM jobpush.career_site_discovery_runs
WHERE run_id='$RUN_ID';

SELECT source_type, count(*) AS new_or_existing_candidates
FROM jobpush.career_sites
WHERE discovery_source='generic_html_link_resolver'
GROUP BY source_type
ORDER BY new_or_existing_candidates DESC, source_type;
"
