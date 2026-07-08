\pset pager off

BEGIN;

UPDATE jobpush.career_sites site
SET site_url = regexp_replace(
        site.site_url,
        '^(https?://recruiting\.ultipro\.com/[^/]+/JobBoard)(?:/[0-9a-f-]{36})?.*$',
        '\1/ListJobs',
        'i'
    ),
    source_key = lower(
        regexp_replace(
            regexp_replace(site.site_url, '^https?://recruiting\.ultipro\.com/', '', 'i'),
            '/[0-9a-f-]{36}.*$',
            '',
            'i'
        )
    ) || '/listjobs',
    updated_at = now(),
    review_notes = concat_ws('; ', site.review_notes, 'Normalized UltiPro board URL to ListJobs entrypoint')
WHERE site.source_type = 'ultipro'
  AND site.normalized_domain = 'recruiting.ultipro.com'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND site.site_url ~* '^https?://recruiting\.ultipro\.com/[^/]+/JobBoard';

UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-phenom-cdn-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Rejected Phenom CDN/asset URL; not an employer career board'),
    updated_at = now()
WHERE site.source_type = 'phenom'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND (
      site.normalized_domain ~* '^(cdn|assets|pp-cdn)\.phenompeople\.com$'
      OR site.normalized_domain ~* '^content-[a-z]{2}\.phenompeople\.com$'
      OR site.site_url ~* 'CareerConnectResources'
      OR site.normalized_domain = 'careers.phenom.com'
  );

UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    reviewed_at = now(),
    reviewed_by = 'system:reject-bad-ultipro-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Rejected non-board UltiPro URL'),
    updated_at = now()
WHERE site.source_type = 'ultipro'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND site.site_url !~* '^https?://recruiting\.ultipro\.com/[^/]+/JobBoard';

COMMIT;

SELECT reviewed_by, count(*) AS sites, count(DISTINCT consolidation_key) AS companies
FROM jobpush.career_sites
WHERE reviewed_by IN ('system:reject-phenom-cdn-v1', 'system:reject-bad-ultipro-v1')
GROUP BY 1
ORDER BY 1;

SELECT count(*) AS normalized_ultipro_sites
FROM jobpush.career_sites
WHERE source_type = 'ultipro'
  AND site_url ~* '/JobBoard/ListJobs$';
