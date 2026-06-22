BEGIN;

INSERT INTO jobpush.career_site_discovery_runs (
    run_id, cohort, target_count, search_count, candidate_count,
    error_count, estimated_credits, status, started_at
)
SELECT
    :'run_id', :'cohort', COUNT(*), COUNT(*),
    COALESCE(SUM(candidate_count), 0),
    COUNT(*) FILTER (WHERE NOT search_succeeded),
    COUNT(*), 'running', now()
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
    stage.consolidation_key, stage.site_url, stage.normalized_domain,
    stage.site_kind, stage.source_type, NULLIF(stage.source_key, ''),
    'tavily_basic', 'unverified', FALSE, 'pending',
    stage.candidate_rank, stage.candidate_score, stage.search_query,
    NULLIF(stage.evidence_title, ''), NULLIF(stage.evidence_snippet, ''),
    now(), now(), now()
FROM jobpush.career_site_discovery_stage stage
WHERE stage.run_id = :'run_id'
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    normalized_domain = EXCLUDED.normalized_domain,
    site_kind = EXCLUDED.site_kind,
    source_type = EXCLUDED.source_type,
    source_key = EXCLUDED.source_key,
    candidate_rank = EXCLUDED.candidate_rank,
    candidate_score = EXCLUDED.candidate_score,
    search_query = EXCLUDED.search_query,
    evidence_title = EXCLUDED.evidence_title,
    evidence_snippet = EXCLUDED.evidence_snippet,
    last_discovered_at = now(),
    updated_at = now();

UPDATE jobpush.crawl_targets target
SET
    discovery_status = CASE
        WHEN result.search_succeeded AND result.candidate_count > 0 THEN 'review_pending'
        WHEN result.search_succeeded THEN 'not_found'
        ELSE 'retry'
    END,
    next_discovery_at = CASE
        WHEN result.search_succeeded AND result.candidate_count > 0 THEN NULL
        WHEN result.search_succeeded THEN now() + INTERVAL '30 days'
        ELSE now() + INTERVAL '1 day'
    END,
    last_discovery_at = now(),
    last_discovery_success_at = CASE
        WHEN result.search_succeeded THEN now()
        ELSE target.last_discovery_success_at
    END,
    consecutive_discovery_failures = CASE
        WHEN result.search_succeeded THEN 0
        ELSE target.consecutive_discovery_failures + 1
    END,
    last_discovery_error = NULLIF(result.error_message, ''),
    updated_at = now()
FROM jobpush.career_site_discovery_result_stage result
WHERE result.run_id = :'run_id'
  AND result.consolidation_key = target.consolidation_key;

UPDATE jobpush.career_site_discovery_runs run
SET status = 'completed', finished_at = now()
WHERE run.run_id = :'run_id';

DELETE FROM jobpush.career_site_discovery_stage WHERE run_id = :'run_id';
DELETE FROM jobpush.career_site_discovery_result_stage WHERE run_id = :'run_id';

COMMIT;
