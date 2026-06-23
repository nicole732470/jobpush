-- United Airlines, Inc. (74-2099724): reject Tavily candidates, verify search-results URL.

BEGIN;

SELECT jobpush.review_career_site(280, 'rejected', 'nicole', 'Legacy Taleo cart page, not job search');
SELECT jobpush.review_career_site(281, 'rejected', 'nicole', 'Careers landing page; jobs at search-results URL');

INSERT INTO jobpush.career_sites (
    consolidation_key, site_url, normalized_domain, site_kind,
    source_type, discovery_source, verification_status,
    crawl_enabled, crawl_status, candidate_rank, evidence_title, review_notes
)
VALUES (
    '74-2099724',
    'https://careers.united.com/us/en/search-results',
    'careers.united.com', 'ats_feed', 'generic_html', 'manual',
    'unverified', FALSE, 'pending', 1,
    'United Airlines job search',
    'Manual override: confirmed United careers search-results URL'
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    site_kind = EXCLUDED.site_kind,
    updated_at = now();

SELECT jobpush.review_career_site(
    site.site_id, 'verified', 'nicole', 'Official United Airlines careers job search'
)
FROM jobpush.career_sites site
WHERE site.consolidation_key = '74-2099724'
  AND site.site_url = 'https://careers.united.com/us/en/search-results';

COMMIT;
