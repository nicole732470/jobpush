-- JPMorgan Chase & Co. (13-2624428): reject Tavily candidates, verify Oracle HCM URL.
-- Prefer db/run_migration_032.sh on RDS.

BEGIN;

SELECT jobpush.review_career_site(84, 'rejected', 'nicole', 'Wrong career-site candidate');
SELECT jobpush.review_career_site(85, 'rejected', 'nicole', 'Wrong career-site candidate');
SELECT jobpush.review_career_site(86, 'rejected', 'nicole', 'Wrong career-site candidate');

INSERT INTO jobpush.career_sites (
    consolidation_key, site_url, normalized_domain, site_kind,
    source_type, source_key, discovery_source, verification_status,
    crawl_enabled, crawl_status, candidate_rank, evidence_title, review_notes
)
VALUES (
    '13-2624428',
    'https://jpmc.fa.oraclecloud.com/hcmUI/CandidateExperience/en/sites/CX_1001/jobs',
    'jpmc.fa.oraclecloud.com', 'ats_feed', 'oracle_cloud', 'CX_1001', 'manual',
    'unverified', FALSE, 'pending', 1,
    'JPMorgan Chase Oracle Cloud HCM job search',
    'Manual override: confirmed Oracle Candidate Experience jobs URL'
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    source_type = EXCLUDED.source_type,
    site_kind = EXCLUDED.site_kind,
    updated_at = now();

SELECT jobpush.review_career_site(
    site.site_id, 'verified', 'nicole',
    'Official JPMorgan Chase Oracle Cloud HCM external job board'
)
FROM jobpush.career_sites site
WHERE site.consolidation_key = '13-2624428'
  AND site.site_url =
      'https://jpmc.fa.oraclecloud.com/hcmUI/CandidateExperience/en/sites/CX_1001/jobs';

COMMIT;
