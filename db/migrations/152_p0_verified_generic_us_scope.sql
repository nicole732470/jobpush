UPDATE jobpush.career_sites
SET target_country_code = 'US',
    scope_method = 'local_filter',
    crawl_status = 'pending',
    next_crawl_at = now(),
    review_notes = concat_ws(' ', NULLIF(review_notes, ''), 'P0 verified URL marked US local-filter on 2026-07-07.'),
    updated_at = now()
WHERE site_id IN (12922, 13076, 57087)
  AND verification_status = 'verified'
  AND crawl_enabled = TRUE;
