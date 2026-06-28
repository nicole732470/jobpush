\pset pager off

BEGIN;

-- Oracle candidates must point at the site board, not /404 or job-detail pages.
WITH bad AS (
    SELECT
        site_id,
        consolidation_key,
        regexp_replace(site_url, '^(https?://[^/]+/hcmUI/CandidateExperience/[^/]+/sites/[^/?#]+).*$','\1/jobs') AS canonical_url,
        substring(site_url from '/sites/([^/?#]+)') AS canonical_key,
        row_number() OVER (
            PARTITION BY consolidation_key, regexp_replace(site_url, '^(https?://[^/]+/hcmUI/CandidateExperience/[^/]+/sites/[^/?#]+).*$','\1/jobs')
            ORDER BY verification_status = 'verified' DESC, crawl_enabled DESC, candidate_score DESC NULLS LAST, site_id
        ) AS keep_rank
    FROM jobpush.career_sites
    WHERE lower(coalesce(normalized_domain, split_part(regexp_replace(site_url, '^https?://', ''), '/', 1))) LIKE '%oraclecloud.com'
      AND site_url ~ '/hcmUI/CandidateExperience/[^/]+/sites/[^/?#]+/(404|job/|jobs/preview|requisitions?)'
), updated AS (
    UPDATE jobpush.career_sites site
    SET site_url = bad.canonical_url,
        normalized_domain = lower(regexp_replace(split_part(regexp_replace(bad.canonical_url, '^https?://', ''), '/', 1), '^www\.', '')),
        site_kind = 'ats_feed',
        source_type = 'oracle_cloud',
        source_key = bad.canonical_key,
        target_country_code = 'US',
        scope_method = 'server_filter',
        crawl_status = 'pending',
        next_crawl_at = CASE WHEN site.verification_status = 'verified' AND site.crawl_enabled THEN now() ELSE site.next_crawl_at END,
        last_error = NULL,
        review_notes = concat_ws('; ', site.review_notes, 'Canonicalized Oracle site URL by 105'),
        updated_at = now()
    FROM bad
    WHERE site.site_id = bad.site_id
      AND bad.keep_rank = 1
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites existing
          WHERE existing.consolidation_key = site.consolidation_key
            AND existing.site_url = bad.canonical_url
            AND existing.site_id <> site.site_id
      )
    RETURNING site.site_id
)
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    last_error = 'rejected_bad_oracle_detail_or_404_url: canonical site already exists',
    review_notes = concat_ws('; ', site.review_notes, 'Rejected duplicate bad Oracle URL by 105'),
    updated_at = now()
FROM bad
WHERE site.site_id = bad.site_id
  AND NOT EXISTS (SELECT 1 FROM updated WHERE updated.site_id = site.site_id);

-- SmartRecruiters API/job-detail URLs must be stored as company boards.
WITH bad AS (
    SELECT
        site_id,
        consolidation_key,
        'https://careers.smartrecruiters.com/' || substring(site_url from 'smartrecruiters\.com/v1/companies/([^/]+)') AS canonical_url,
        substring(site_url from 'smartrecruiters\.com/v1/companies/([^/]+)') AS canonical_key,
        row_number() OVER (
            PARTITION BY consolidation_key, substring(site_url from 'smartrecruiters\.com/v1/companies/([^/]+)')
            ORDER BY verification_status = 'verified' DESC, crawl_enabled DESC, candidate_score DESC NULLS LAST, site_id
        ) AS keep_rank
    FROM jobpush.career_sites
    WHERE site_url ~ '^https?://api\.smartrecruiters\.com/v1/companies/[^/]+/postings'
), updated AS (
    UPDATE jobpush.career_sites site
    SET site_url = bad.canonical_url,
        normalized_domain = 'careers.smartrecruiters.com',
        site_kind = 'ats_feed',
        source_type = 'smartrecruiters',
        source_key = bad.canonical_key,
        target_country_code = 'US',
        scope_method = 'local_filter',
        crawl_status = 'pending',
        next_crawl_at = CASE WHEN site.verification_status = 'verified' AND site.crawl_enabled THEN now() ELSE site.next_crawl_at END,
        last_error = NULL,
        review_notes = concat_ws('; ', site.review_notes, 'Canonicalized SmartRecruiters API/detail URL by 105'),
        updated_at = now()
    FROM bad
    WHERE site.site_id = bad.site_id
      AND bad.keep_rank = 1
      AND bad.canonical_key IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites existing
          WHERE existing.consolidation_key = site.consolidation_key
            AND existing.site_url = bad.canonical_url
            AND existing.site_id <> site.site_id
      )
    RETURNING site.site_id
)
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    last_error = 'rejected_bad_smartrecruiters_api_detail_url: canonical site already exists',
    review_notes = concat_ws('; ', site.review_notes, 'Rejected duplicate SmartRecruiters API/detail URL by 105'),
    updated_at = now()
FROM bad
WHERE site.site_id = bad.site_id
  AND NOT EXISTS (SELECT 1 FROM updated WHERE updated.site_id = site.site_id);

COMMIT;

SELECT source_type, verification_status, crawl_enabled, count(*) AS affected_sites
FROM jobpush.career_sites
WHERE review_notes LIKE '% by 105%'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
