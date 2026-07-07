UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:catsone-parser-v1',
    review_notes = concat_ws('; ', review_notes, 'Rejected CATS vendor/shared URL after 404 during parser rollout'),
    last_error = 'rejected_bad_catsone_vendor_or_stale_url',
    updated_at = now()
WHERE source_type = 'catsone'
  AND verification_status = 'verified'
  AND crawl_enabled
  AND normalized_domain = 'careers.catsone.com'
  AND crawl_status = 'failed';

SELECT source_type, verification_status, crawl_enabled, crawl_status, count(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_by = 'system:catsone-parser-v1'
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;
