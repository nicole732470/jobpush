BEGIN;

UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    last_error = 'rejected_obvious_bad_structured_candidate',
    review_notes = concat_ws('; ', site.review_notes, 'Rejected obvious non-career ATS candidate by 123'),
    updated_at = now()
WHERE site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND (
      (site.source_type = 'icims' AND site.normalized_domain = 'icims.com')
      OR (site.source_type = 'successfactors' AND site.normalized_domain = 'rmkcdn.successfactors.com')
      OR (site.source_type = 'successfactors' AND site.site_url ~* '/(jquery|vmod_|extlib|[a-f0-9-]{20,}).*\\.(js|jpg|png|gif)$')
      OR (site.source_type = 'eightfold' AND site.normalized_domain = 'eightfold.ai')
      OR (site.source_type = 'eightfold' AND site.site_url LIKE '%\"%')
      OR (site.source_type = 'comeet' AND site.normalized_domain = 'help.comeet.com')
  );

COMMIT;

SELECT source_type, normalized_domain, count(*) AS rejected_sites
FROM jobpush.career_sites
WHERE review_notes LIKE '%Rejected obvious non-career ATS candidate by 123%'
GROUP BY 1, 2
ORDER BY rejected_sites DESC, source_type, normalized_domain;
