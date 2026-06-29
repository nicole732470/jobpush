BEGIN;

CREATE TEMP TABLE duplicate_company_adapter_sites AS
WITH ranked AS (
    SELECT site.site_id,
           ROW_NUMBER() OVER (
               PARTITION BY site.consolidation_key, site.source_type
               ORDER BY site.last_success_at DESC NULLS LAST, site.site_id
           ) AS keep_rank
    FROM jobpush.career_sites site
    WHERE site.source_type IN ('amazon_jobs', 'cognizant_jobs')
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
)
SELECT site_id
FROM ranked
WHERE keep_rank > 1;

UPDATE jobpush.career_sites site
SET crawl_enabled = FALSE,
    crawl_status = 'pending',
    next_crawl_at = NULL,
    review_notes = concat_ws('; ', site.review_notes, 'Disabled duplicate enabled site for same company/source_type; kept one canonical adapter site'),
    updated_at = now()
FROM duplicate_company_adapter_sites duplicate
WHERE site.site_id = duplicate.site_id;

UPDATE jobpush.job_postings posting
SET active = FALSE,
    closed_at = COALESCE(posting.closed_at, now()),
    updated_at = now()
FROM duplicate_company_adapter_sites duplicate
WHERE posting.site_id = duplicate.site_id
  AND posting.active;

SELECT COUNT(*) AS duplicate_sites_disabled
FROM duplicate_company_adapter_sites;

COMMIT;
