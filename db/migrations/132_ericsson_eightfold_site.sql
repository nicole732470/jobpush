BEGIN;

INSERT INTO jobpush.career_sites (
    consolidation_key,
    site_url,
    normalized_domain,
    site_kind,
    source_type,
    source_key,
    target_country_code,
    scope_method,
    candidate_rank,
    candidate_score,
    verification_status,
    crawl_enabled,
    crawl_status,
    discovery_source,
    reviewed_by,
    reviewed_at,
    next_crawl_at,
    created_at,
    updated_at
)
VALUES (
    'ericsson',
    'https://jobs.ericsson.com/careers',
    'jobs.ericsson.com',
    'ats_feed',
    'eightfold',
    'jobs.ericsson.com',
    'US',
    'local_filter',
    1,
    100,
    'verified',
    TRUE,
    'pending',
    'manual_repair',
    'system:ericsson-eightfold-repair-v1',
    now(),
    now(),
    now(),
    now()
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE
SET
    normalized_domain = EXCLUDED.normalized_domain,
    site_kind = EXCLUDED.site_kind,
    source_type = EXCLUDED.source_type,
    source_key = EXCLUDED.source_key,
    target_country_code = 'US',
    scope_method = 'local_filter',
    candidate_rank = LEAST(coalesce(jobpush.career_sites.candidate_rank, EXCLUDED.candidate_rank), EXCLUDED.candidate_rank),
    candidate_score = GREATEST(coalesce(jobpush.career_sites.candidate_score, 0), EXCLUDED.candidate_score),
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    discovery_source = EXCLUDED.discovery_source,
    reviewed_by = EXCLUDED.reviewed_by,
    reviewed_at = now(),
    next_crawl_at = now(),
    last_error = NULL,
    updated_at = now();

COMMIT;

\pset pager off

SELECT site_id, consolidation_key, source_type, site_url, crawl_enabled, crawl_status, next_crawl_at
FROM jobpush.career_sites
WHERE consolidation_key = 'ericsson'
ORDER BY crawl_enabled DESC, source_type, site_id;
