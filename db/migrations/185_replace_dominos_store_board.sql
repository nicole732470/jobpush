BEGIN;

-- The SmartRecruiters "Dominos" board mixes corporate and franchise store
-- hiring. It was also attached to DOMINO TECHNOLOGIES by a name collision,
-- causing the same 2,000-row page cap to be crawled twice.
UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:dominos-corporate-source-v1',
    review_notes = concat_ws('; ', review_notes,
        'Rejected broad Domino''s SmartRecruiters board; it mixes corporate and franchise store roles.'),
    updated_at = now()
WHERE source_type = 'smartrecruiters'
  AND lower(coalesce(source_key, '')) = 'dominos';

-- Reject the Domino's Pizza IT page that discovery assigned to the unrelated
-- DOMINO TECHNOLOGIES legal entity.
UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:dominos-corporate-source-v1',
    review_notes = concat_ws('; ', review_notes,
        'Rejected Domino''s Pizza page assigned to unrelated DOMINO TECHNOLOGIES by name collision.'),
    updated_at = now()
WHERE consolidation_key = '25-1796494'
  AND normalized_domain = 'jobs.dominos.com';

-- Crawl the official US corporate page under the correct Domino's Pizza
-- company. Normal title classification still decides which corporate roles
-- are targets.
UPDATE jobpush.career_sites
SET normalized_domain = 'jobs.dominos.com',
    site_kind = 'careers',
    source_type = 'generic_html',
    source_key = 'jobs.dominos.com/us/jobs/corporate',
    target_country_code = 'US',
    scope_method = 'verified_us_only',
    candidate_rank = 1,
    candidate_score = GREATEST(coalesce(candidate_score, 0), 100),
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    next_crawl_at = now(),
    consecutive_failures = 0,
    last_error = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:dominos-corporate-source-v1',
    review_notes = concat_ws('; ', review_notes,
        'Verified official Domino''s US corporate jobs page; excludes franchise store board.'),
    updated_at = now()
WHERE consolidation_key = '38-2511577'
  AND site_url = 'https://jobs.dominos.com/us/jobs/corporate';

COMMIT;

SELECT site_id, consolidation_key, site_url, source_type,
       verification_status, crawl_enabled, crawl_status
FROM jobpush.career_sites
WHERE lower(coalesce(source_key, '')) = 'dominos'
   OR site_url = 'https://jobs.dominos.com/us/jobs/corporate'
   OR (consolidation_key = '25-1796494' AND normalized_domain = 'jobs.dominos.com')
ORDER BY site_id;
