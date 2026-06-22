BEGIN;

UPDATE jobpush.career_sites
SET source_type = 'oracle_cloud',
    source_key = 'CX',
    site_kind = 'ats_feed',
    target_country_code = 'US',
    updated_at = now()
WHERE consolidation_key = '75-0289970'
  AND site_url = 'https://edbz.fa.us2.oraclecloud.com/hcmUI/CandidateExperience/en/sites/CX/jobs';

COMMIT;
