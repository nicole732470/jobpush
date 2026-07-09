#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off <<'SQL'
\echo '=== High-volume review titles by source/company ==='
WITH latest AS (
    SELECT DISTINCT ON (run.site_id)
           run.site_id, run.raw_job_count, run.review_job_count
    FROM jobpush.crawl_runs run
    ORDER BY run.site_id, run.started_at DESC NULLS LAST, run.run_id DESC
), noisy_sites AS (
    SELECT site.site_id,
           site.source_type,
           target.priority_tier,
           target.canonical_name,
           latest.raw_job_count,
           latest.review_job_count
    FROM latest
    JOIN jobpush.career_sites site USING (site_id)
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE site.verification_status = 'verified'
      AND site.crawl_enabled
      AND (
          latest.raw_job_count >= 700
          OR latest.review_job_count >= 150
          OR site.source_type IN ('amazon_jobs', 'smartrecruiters')
      )
), ranked AS (
    SELECT noisy_sites.source_type,
           noisy_sites.priority_tier,
           noisy_sites.canonical_name,
           posting.normalized_title,
           min(posting.title) AS example_title,
           count(*) AS active_us_postings,
           row_number() OVER (
               PARTITION BY noisy_sites.source_type
               ORDER BY count(*) DESC, posting.normalized_title
           ) AS source_rank
    FROM noisy_sites
    JOIN jobpush.job_postings posting USING (site_id)
    JOIN jobpush.job_title_labels label USING (normalized_title)
    WHERE posting.active
      AND COALESCE(posting.market_scope, 'US') = 'US'
      AND label.classification_status = 'review'
    GROUP BY 1,2,3,4
)
SELECT source_type, priority_tier, canonical_name, normalized_title, example_title, active_us_postings
FROM ranked
WHERE source_rank <= 20
ORDER BY source_type, source_rank;

\echo '=== Current Jobs-to-Apply pressure by high-volume source ==='
SELECT site.source_type,
       target.priority_tier,
       count(*) AS active_target_jobs,
       count(DISTINCT target.consolidation_key) AS companies
FROM jobpush.dashboard_jobs_fast job
JOIN jobpush.career_sites site
  ON site.site_id = job.site_id
JOIN jobpush.crawl_targets target
  ON target.consolidation_key = job.consolidation_key
WHERE job.role_status = 'target'
  AND site.source_type IN ('amazon_jobs', 'smartrecruiters', 'workday', 'greenhouse')
GROUP BY 1,2
ORDER BY active_target_jobs DESC;
SQL
