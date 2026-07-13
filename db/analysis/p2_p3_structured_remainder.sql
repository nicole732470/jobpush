\pset pager off

\echo '=== Rank-1 structured unverified (no enabled verified site) by source_type ==='
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier,
         site.site_id,
         site.consolidation_key,
         site.source_type,
         site.normalized_domain,
         site.site_url,
         site.candidate_rank,
         site.candidate_score,
         site.last_error,
         site.consecutive_failures
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P2','P3')
    AND site.verification_status = 'unverified'
    AND site.source_type <> 'generic_html'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites enabled
      WHERE enabled.consolidation_key = site.consolidation_key
        AND enabled.verification_status = 'verified'
        AND enabled.crawl_enabled
    )
  ORDER BY site.consolidation_key,
           site.candidate_rank NULLS LAST,
           site.candidate_score DESC NULLS LAST,
           site.site_id
)
SELECT priority_tier, source_type, count(*) AS companies
FROM rank1
GROUP BY 1, 2
ORDER BY 1, companies DESC;

\echo '=== URL shape / block reason ==='
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier,
         site.site_id,
         site.consolidation_key,
         site.source_type,
         site.normalized_domain,
         site.site_url,
         site.last_error,
         site.consecutive_failures
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P2','P3')
    AND site.verification_status = 'unverified'
    AND site.source_type <> 'generic_html'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites enabled
      WHERE enabled.consolidation_key = site.consolidation_key
        AND enabled.verification_status = 'verified'
        AND enabled.crawl_enabled
    )
  ORDER BY site.consolidation_key,
           site.candidate_rank NULLS LAST,
           site.candidate_score DESC NULLS LAST,
           site.site_id
)
SELECT
  priority_tier,
  source_type,
  CASE
    WHEN source_type = 'workday'
         AND site_url ~* 'myworkdayjobs\.com/.*/job/'
      THEN 'detail_workday_job'
    WHEN source_type = 'amazon_jobs'
         AND site_url ~* 'amazon\.jobs/.*/jobs/[0-9]+/'
      THEN 'detail_amazon_job'
    WHEN source_type = 'oracle_cloud'
         AND site_url ~ '/hcmUI/CandidateExperience/.*/sites/[^/?#]+/(404|job/|jobs/preview|requisitions?)'
      THEN 'detail_or_bad_oracle'
    WHEN source_type = 'oracle_cloud'
         AND site_url ~ '/hcmUI/CandidateExperience/.*/sites/[^/?#]+$'
      THEN 'oracle_missing_jobs_suffix'
    WHEN source_type = 'smartrecruiters'
         AND site_url ~ 'api\.smartrecruiters\.com/v1/companies/.+/postings'
      THEN 'smartrecruiters_api_detail'
    WHEN source_type = 'greenhouse'
         AND site_url ~* '(greenhouse\.io/.+/.+|boards\.greenhouse\.io/.+/jobs/)'
      THEN 'greenhouse_job_or_nested'
    WHEN source_type = 'lever'
         AND site_url ~* 'jobs\.lever\.co/[^/]+/.+'
      THEN 'lever_job_detail'
    WHEN source_type = 'ashby'
         AND site_url ~* 'jobs\.ashbyhq\.com/[^/]+/.+'
      THEN 'ashby_job_detail'
    WHEN source_type = 'workable'
         AND normalized_domain = 'jobs.workable.com'
      THEN 'workable_jobs_landing_not_apply'
    WHEN source_type = 'workable'
         AND normalized_domain <> 'apply.workable.com'
      THEN 'workable_wrong_domain'
    WHEN source_type = 'icims' AND normalized_domain = 'icims.com'
      THEN 'icims_vendor_root'
    WHEN source_type = 'icims'
         AND site_url ~* '(icims\.com/legal|/privacy|/jobs/login$|internal[-.])'
      THEN 'icims_login_privacy_internal'
    WHEN source_type = 'icims'
         AND consecutive_failures >= 2
         AND coalesce(last_error,'') ~* 'timeout|timed out'
      THEN 'icims_chronic_timeout'
    WHEN source_type = 'ultipro'
         AND site_url !~* '/jobboard/listjobs$'
      THEN 'ultipro_missing_listjobs'
    WHEN source_type IN (
           'greenhouse','workday','lever','ashby','smartrecruiters','oracle_cloud',
           'amazon_jobs','jobvite','paylocity','rippling','applytojob','catsone',
           'trakstar','breezy','dover'
         )
         OR (source_type = 'workable' AND normalized_domain = 'apply.workable.com')
         OR (source_type = 'icims' AND normalized_domain LIKE '%.icims.com'
             AND normalized_domain <> 'icims.com')
         OR (source_type = 'ultipro' AND site_url ~* '/jobboard/listjobs$')
      THEN 'should_be_autotrust_eligible'
    WHEN source_type IN (
           'eightfold','phenom','successfactors','brassring','talentbrew',
           'trinethire','comeet','jobscore','gusto','applicantpro','google_jobs',
           'uber_jobs','apple_jobs','cognizant_jobs','unknown'
         )
      THEN 'identify_only_or_no_parser'
    ELSE 'other_unsupported'
  END AS url_shape_or_block,
  count(*) AS companies
FROM rank1
GROUP BY 1, 2, 3
ORDER BY 1, companies DESC, source_type, url_shape_or_block;

\echo '=== Sample should_be_autotrust_eligible (investigate) ==='
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier,
         site.site_id,
         site.consolidation_key,
         target.canonical_name,
         site.source_type,
         site.normalized_domain,
         site.site_url,
         site.candidate_rank
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P2','P3')
    AND site.verification_status = 'unverified'
    AND site.source_type <> 'generic_html'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites enabled
      WHERE enabled.consolidation_key = site.consolidation_key
        AND enabled.verification_status = 'verified'
        AND enabled.crawl_enabled
    )
  ORDER BY site.consolidation_key,
           site.candidate_rank NULLS LAST,
           site.candidate_score DESC NULLS LAST,
           site.site_id
)
SELECT priority_tier, site_id, consolidation_key, canonical_name, source_type, site_url
FROM rank1
WHERE source_type IN (
           'greenhouse','workday','lever','ashby','smartrecruiters','oracle_cloud',
           'amazon_jobs','jobvite','paylocity','rippling','applytojob','catsone',
           'trakstar','breezy','dover'
         )
   OR (source_type = 'workable' AND normalized_domain = 'apply.workable.com')
   OR (source_type = 'icims' AND normalized_domain LIKE '%.icims.com'
       AND normalized_domain <> 'icims.com'
       AND site_url !~* '(icims\.com/legal|/privacy|/jobs/login$|internal[-.])')
   OR (source_type = 'ultipro' AND site_url ~* '/jobboard/listjobs$')
ORDER BY priority_tier, source_type, site_id
LIMIT 40;

\echo '=== Failed first crawls: system:generic-jsonld-v1 ==='
SELECT target.priority_tier,
       site.crawl_status,
       count(*) AS sites,
       count(*) FILTER (WHERE site.last_success_at IS NULL) AS never_succeeded
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:generic-jsonld-v1'
  AND target.priority_tier IN ('P2','P3')
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '=== Failed first crawl detail ==='
SELECT target.priority_tier, target.canonical_name, site.site_id,
       left(site.site_url, 90) AS site_url,
       site.crawl_status, site.consecutive_failures,
       left(coalesce(site.last_error,''), 120) AS last_error
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:generic-jsonld-v1'
  AND target.priority_tier IN ('P2','P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND (site.crawl_status = 'failed' OR site.last_success_at IS NULL)
ORDER BY target.priority_tier, target.priority_score DESC;
