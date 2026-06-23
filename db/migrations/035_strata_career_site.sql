BEGIN;

SELECT jobpush.review_career_site(
    115, 'rejected', 'nicole', 'Corporate marketing page; jobs on Greenhouse'
);

INSERT INTO jobpush.career_sites (
    consolidation_key,
    site_url,
    normalized_domain,
    site_kind,
    source_type,
    source_key,
    discovery_source,
    verification_status,
    crawl_enabled,
    crawl_status,
    candidate_rank,
    evidence_title,
    review_notes,
    created_at,
    updated_at
)
VALUES (
    '32-0368502',
    'https://job-boards.greenhouse.io/stratacareers',
    'job-boards.greenhouse.io',
    'ats_feed',
    'greenhouse',
    'stratacareers',
    'manual',
    'unverified',
    FALSE,
    'pending',
    1,
    'Strata Decision Technology Greenhouse job board',
    'Manual override: confirmed Greenhouse careers URL',
    now(),
    now()
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    normalized_domain = EXCLUDED.normalized_domain,
    site_kind = EXCLUDED.site_kind,
    source_type = EXCLUDED.source_type,
    source_key = EXCLUDED.source_key,
    discovery_source = EXCLUDED.discovery_source,
    evidence_title = EXCLUDED.evidence_title,
    review_notes = EXCLUDED.review_notes,
    updated_at = now();

SELECT jobpush.review_career_site(
    site.site_id,
    'verified',
    'nicole',
    'Official Strata Decision Technology Greenhouse job board'
)
FROM jobpush.career_sites site
WHERE site.consolidation_key = '32-0368502'
  AND site.site_url = 'https://job-boards.greenhouse.io/stratacareers';

UPDATE jobpush.crawl_targets
SET
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = '32-0368502';

COMMIT;
