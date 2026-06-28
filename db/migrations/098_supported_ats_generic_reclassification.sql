\pset pager off

BEGIN;

-- ponytail: reclassify only supported ATS domains; no speculative parser.
UPDATE jobpush.career_sites
SET source_type = 'greenhouse',
    source_key = split_part(regexp_replace(site_url, '^https?://[^/]+/', ''), '/', 1),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 098')
WHERE source_type = 'generic_html'
  AND normalized_domain IN ('boards.greenhouse.io', 'job-boards.greenhouse.io');

UPDATE jobpush.career_sites
SET source_type = 'lever',
    source_key = split_part(regexp_replace(site_url, '^https?://[^/]+/', ''), '/', 1),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 098')
WHERE source_type = 'generic_html'
  AND normalized_domain IN ('jobs.lever.co', 'jobs.eu.lever.co');

UPDATE jobpush.career_sites
SET source_type = 'ashby',
    source_key = split_part(regexp_replace(site_url, '^https?://[^/]+/', ''), '/', 1),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 098')
WHERE source_type = 'generic_html'
  AND normalized_domain = 'jobs.ashbyhq.com';

UPDATE jobpush.career_sites
SET source_type = 'smartrecruiters',
    source_key = split_part(regexp_replace(site_url, '^https?://[^/]+/', ''), '/', 1),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 098')
WHERE source_type = 'generic_html'
  AND normalized_domain = 'careers.smartrecruiters.com';

UPDATE jobpush.career_sites
SET source_type = 'oracle_cloud',
    source_key = normalized_domain,
    site_kind = 'ats_feed',
    target_country_code = 'US',
    scope_method = 'server_filter',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 098')
WHERE source_type = 'generic_html'
  AND normalized_domain LIKE '%oraclecloud.com'
  AND site_url ILIKE '%/hcmUI/CandidateExperience/%';

COMMIT;

SELECT source_type, verification_status, crawl_enabled, count(*) AS sites
FROM jobpush.career_sites
WHERE review_notes LIKE '%Reclassified from generic_html by 098%'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
