BEGIN;

UPDATE jobpush.career_sites
SET target_country_code = 'US',
    source_type = 'oracle_cloud',
    source_key = 'CX_1001',
    site_kind = 'ats_feed',
    updated_at = now()
WHERE consolidation_key = '13-2624428'
  AND site_url = 'https://jpmc.fa.oraclecloud.com/hcmUI/CandidateExperience/en/sites/CX_1001/jobs';

COMMIT;
