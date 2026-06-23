BEGIN;

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
SELECT
    key.consolidation_key,
    'https://www.google.com/about/careers/applications/jobs/results?location=United%20States',
    'www.google.com',
    'ats_feed',
    'generic_html',
    NULL,
    'manual',
    'unverified',
    FALSE,
    'pending',
    1,
    'Google careers job search (United States)',
    'Manual override: confirmed Google careers results URL',
    now(),
    now()
FROM (VALUES ('google'), ('alphabet-google')) AS key(consolidation_key)
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
    'Official Google careers job search (US)'
)
FROM jobpush.career_sites site
WHERE site.consolidation_key IN ('google', 'alphabet-google')
  AND site.site_url =
      'https://www.google.com/about/careers/applications/jobs/results?location=United%20States';

UPDATE jobpush.crawl_targets
SET
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key IN ('google', 'alphabet-google');

COMMIT;
