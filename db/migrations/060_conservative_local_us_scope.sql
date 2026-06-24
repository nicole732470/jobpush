BEGIN;

-- Greenhouse and Workday adapters now classify each posting conservatively
-- from its location. Ambiguous locations remain unknown and never enter the
-- job_postings_us view. iCIMS applies its own server-side US location filter.
UPDATE jobpush.career_sites
SET target_country_code = 'US',
    scope_method = CASE source_type
        WHEN 'icims' THEN 'server_filter'
        ELSE 'local_filter'
    END,
    next_crawl_at = now(),
    updated_at = now()
WHERE verification_status = 'verified'
  AND crawl_enabled
  AND source_type IN ('greenhouse', 'workday', 'icims')
  AND (target_country_code IS DISTINCT FROM 'US' OR scope_method = 'unknown');

COMMIT;
