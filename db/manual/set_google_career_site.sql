-- Google / Alphabet-Google: verify official careers results URL (US).

BEGIN;

INSERT INTO jobpush.career_sites (
    consolidation_key, site_url, normalized_domain, site_kind,
    source_type, discovery_source, verification_status,
    crawl_enabled, crawl_status, candidate_rank, evidence_title, review_notes
)
SELECT
    key.consolidation_key,
    'https://www.google.com/about/careers/applications/jobs/results?location=United%20States',
    'www.google.com', 'ats_feed', 'generic_html', 'manual',
    'unverified', FALSE, 'pending', 1,
    'Google careers job search (United States)',
    'Manual override: confirmed Google careers results URL'
FROM (VALUES ('google'), ('alphabet-google')) AS key(consolidation_key)
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET updated_at = now();

SELECT jobpush.review_career_site(
    site.site_id, 'verified', 'nicole', 'Official Google careers job search (US)'
)
FROM jobpush.career_sites site
WHERE site.consolidation_key IN ('google', 'alphabet-google')
  AND site.site_url =
      'https://www.google.com/about/careers/applications/jobs/results?location=United%20States';

COMMIT;
