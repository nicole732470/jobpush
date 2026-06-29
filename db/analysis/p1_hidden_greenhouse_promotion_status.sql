\pset pager off

WITH promoted_sites AS (
  SELECT
    target.priority_tier,
    row_number() OVER (
      ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name
    ) AS promoted_rank,
    target.priority_score,
    target.canonical_name,
    site.site_id,
    site.site_url,
    site.source_type,
    site.source_key,
    site.crawl_status,
    site.last_success_at,
    site.last_error,
    site.last_crawled_at
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target
    ON target.consolidation_key = site.consolidation_key
  WHERE site.reviewed_by = 'system:p1-hidden-greenhouse-v1'
)
SELECT
  promoted.priority_tier,
  promoted.promoted_rank,
  promoted.canonical_name,
  promoted.site_id,
  promoted.source_key,
  promoted.crawl_status,
  promoted.last_success_at,
  COUNT(posting.external_job_id) FILTER (
    WHERE posting.first_seen_at >= now() - interval '24 hours'
  ) AS jobs_seen_24h,
  COUNT(posting.external_job_id) AS total_jobs_in_db,
  promoted.last_error
FROM promoted_sites promoted
LEFT JOIN jobpush.job_postings posting
  ON posting.site_id = promoted.site_id
GROUP BY
  promoted.priority_tier,
  promoted.promoted_rank,
  promoted.priority_score,
  promoted.canonical_name,
  promoted.site_id,
  promoted.source_key,
  promoted.crawl_status,
  promoted.last_success_at,
  promoted.last_error
ORDER BY promoted.priority_score DESC, promoted.canonical_name;
