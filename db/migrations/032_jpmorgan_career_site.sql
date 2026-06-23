BEGIN;

SELECT jobpush.review_career_site(
    84, 'rejected', 'nicole', 'Corporate marketing page, not job feed'
);
SELECT jobpush.review_career_site(
    85, 'rejected', 'nicole', 'Wrong career-site candidate'
);
SELECT jobpush.review_career_site(
    86, 'rejected', 'nicole', 'Wrong career-site candidate'
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
    '13-2624428',
    'https://jpmc.fa.oraclecloud.com/hcmUI/CandidateExperience/en/sites/CX_1001/jobs',
    'jpmc.fa.oraclecloud.com',
    'ats_feed',
    'oracle_cloud',
    'CX_1001',
    'manual',
    'unverified',
    FALSE,
    'pending',
    1,
    'JPMorgan Chase Oracle Cloud HCM job search',
    'Manual override: confirmed Oracle Candidate Experience jobs URL',
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
    'Official JPMorgan Chase Oracle Cloud HCM external job board'
)
FROM jobpush.career_sites site
WHERE site.consolidation_key = '13-2624428'
  AND site.site_url =
      'https://jpmc.fa.oraclecloud.com/hcmUI/CandidateExperience/en/sites/CX_1001/jobs';

UPDATE jobpush.crawl_targets
SET
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = '13-2624428';

COMMIT;
