\pset pager off

BEGIN;

UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    last_error = 'rejected_bad_greenhouse_embed_url: missing company board slug',
    review_notes = concat_ws('; ', review_notes, 'Rejected invalid Greenhouse embed URL by 106'),
    updated_at = now()
WHERE source_type = 'greenhouse'
  AND site_url ~ '^https?://(boards|job-boards)\.greenhouse\.io/embed/?$'
  AND site_url NOT LIKE '%?for=%';

COMMIT;

SELECT verification_status, crawl_enabled, count(*) AS affected_sites
FROM jobpush.career_sites
WHERE review_notes LIKE '%Greenhouse embed URL by 106%'
GROUP BY 1, 2
ORDER BY 1, 2;
