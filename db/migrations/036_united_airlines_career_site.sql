BEGIN;

SELECT jobpush.review_career_site(
    280, 'rejected', 'nicole', 'Legacy Taleo cart page, not job search'
);
SELECT jobpush.review_career_site(
    281, 'rejected', 'nicole', 'Careers landing page; jobs at search-results URL'
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
    '74-2099724',
    'https://careers.united.com/us/en/search-results',
    'careers.united.com',
    'ats_feed',
    'generic_html',
    NULL,
    'manual',
    'unverified',
    FALSE,
    'pending',
    1,
    'United Airlines job search',
    'Manual override: confirmed United careers search-results URL',
    now(),
    now()
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    normalized_domain = EXCLUDED.normalized_domain,
    site_kind = EXCLUDED.site_kind,
    discovery_source = EXCLUDED.discovery_source,
    evidence_title = EXCLUDED.evidence_title,
    review_notes = EXCLUDED.review_notes,
    updated_at = now();

SELECT jobpush.review_career_site(
    site.site_id,
    'verified',
    'nicole',
    'Official United Airlines careers job search'
)
FROM jobpush.career_sites site
WHERE site.consolidation_key = '74-2099724'
  AND site.site_url = 'https://careers.united.com/us/en/search-results';

UPDATE jobpush.crawl_targets
SET
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = '74-2099724';

COMMIT;
