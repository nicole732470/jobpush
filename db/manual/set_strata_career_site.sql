-- Strata Decision Technology, LLC (32-0368502): reject Tavily candidate, verify Greenhouse URL.
-- Prefer db/run_migration_035.sh on RDS.

BEGIN;

SELECT jobpush.review_career_site(
    115, 'rejected', 'nicole', 'Corporate marketing page; jobs on Greenhouse'
);

INSERT INTO jobpush.career_sites (
    consolidation_key, site_url, normalized_domain, site_kind,
    source_type, source_key, discovery_source, verification_status,
    crawl_enabled, crawl_status, candidate_rank, evidence_title, review_notes
)
VALUES (
    '32-0368502',
    'https://job-boards.greenhouse.io/stratacareers',
    'job-boards.greenhouse.io', 'ats_feed', 'greenhouse', 'stratacareers', 'manual',
    'unverified', FALSE, 'pending', 1,
    'Strata Decision Technology Greenhouse job board',
    'Manual override: confirmed Greenhouse careers URL'
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    source_type = EXCLUDED.source_type,
    site_kind = EXCLUDED.site_kind,
    updated_at = now();

SELECT jobpush.review_career_site(
    site.site_id, 'verified', 'nicole',
    'Official Strata Decision Technology Greenhouse job board'
)
FROM jobpush.career_sites site
WHERE site.consolidation_key = '32-0368502'
  AND site.site_url = 'https://job-boards.greenhouse.io/stratacareers';

COMMIT;
