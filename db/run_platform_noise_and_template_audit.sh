#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
\echo '=== High-volume enabled platform crawls (latest run per site) ==='
WITH latest AS (
    SELECT DISTINCT ON (run.site_id)
           run.site_id,
           run.run_id,
           run.status,
           run.started_at,
           run.finished_at,
           run.raw_job_count,
           run.target_job_count,
           run.review_job_count,
           run.new_job_count,
           run.error_message
    FROM jobpush.crawl_runs run
    ORDER BY run.site_id, run.started_at DESC NULLS LAST, run.run_id DESC
)
SELECT target.priority_tier,
       target.canonical_name,
       site.source_type,
       site.site_id,
       latest.status,
       latest.raw_job_count,
       latest.target_job_count,
       latest.review_job_count,
       latest.new_job_count,
       round(100.0 * COALESCE(latest.target_job_count, 0) / NULLIF(latest.raw_job_count, 0), 1) AS target_pct,
       round(100.0 * COALESCE(latest.review_job_count, 0) / NULLIF(latest.raw_job_count, 0), 1) AS review_pct,
       latest.finished_at,
       site.site_url
FROM latest
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.verification_status = 'verified'
  AND site.crawl_enabled
  AND COALESCE(latest.raw_job_count, 0) >= 100
ORDER BY latest.raw_job_count DESC NULLS LAST
LIMIT 35;

\echo '=== Platform source summary for enabled sites ==='
SELECT site.source_type,
       target.priority_tier,
       COUNT(*) AS enabled_sites,
       COUNT(*) FILTER (WHERE site.last_success_at IS NOT NULL) AS succeeded_once,
       COUNT(*) FILTER (WHERE site.crawl_status = 'failed') AS failed_sites,
       SUM(COALESCE(latest.raw_job_count, 0)) AS latest_raw_jobs,
       SUM(COALESCE(latest.target_job_count, 0)) AS latest_target_jobs,
       SUM(COALESCE(latest.review_job_count, 0)) AS latest_review_jobs
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN LATERAL (
    SELECT run.raw_job_count, run.target_job_count, run.review_job_count
    FROM jobpush.crawl_runs run
    WHERE run.site_id = site.site_id
    ORDER BY run.started_at DESC NULLS LAST, run.run_id DESC
    LIMIT 1
) latest ON TRUE
WHERE site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.source_type NOT IN ('manual')
GROUP BY 1, 2
ORDER BY latest_raw_jobs DESC NULLS LAST, enabled_sites DESC;

\echo '=== Review/noise title pressure from high-volume sites ==='
WITH high_volume_sites AS (
    SELECT site.site_id,
           site.source_type,
           target.priority_tier,
           target.canonical_name
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    JOIN LATERAL (
        SELECT run.raw_job_count
        FROM jobpush.crawl_runs run
        WHERE run.site_id = site.site_id
        ORDER BY run.started_at DESC NULLS LAST, run.run_id DESC
        LIMIT 1
    ) latest ON TRUE
    WHERE site.verification_status = 'verified'
      AND site.crawl_enabled
      AND COALESCE(latest.raw_job_count, 0) >= 100
)
SELECT COALESCE(label.classification_status, 'unlabeled') AS title_status,
       posting.normalized_title,
       min(posting.title) AS example_title,
       COUNT(*) AS active_us_postings,
       COUNT(DISTINCT posting.consolidation_key) AS companies,
       string_agg(DISTINCT high_volume_sites.source_type, ', ' ORDER BY high_volume_sites.source_type) AS source_types,
       string_agg(DISTINCT high_volume_sites.priority_tier, ', ' ORDER BY high_volume_sites.priority_tier) AS tiers
FROM jobpush.job_postings posting
JOIN high_volume_sites ON high_volume_sites.site_id = posting.site_id
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE posting.active
  AND COALESCE(posting.market_scope, 'US') = 'US'
GROUP BY 1, 2
ORDER BY CASE COALESCE(label.classification_status, 'unlabeled')
           WHEN 'review' THEN 0
           WHEN 'target' THEN 1
           WHEN 'unlabeled' THEN 2
           ELSE 3
         END,
         active_us_postings DESC
LIMIT 50;

\echo '=== High-volume sites needing platform-level noise audit ==='
WITH latest AS (
    SELECT DISTINCT ON (run.site_id)
           run.site_id,
           run.status,
           run.started_at,
           run.finished_at,
           run.raw_job_count,
           run.target_job_count,
           run.review_job_count,
           run.new_job_count
    FROM jobpush.crawl_runs run
    ORDER BY run.site_id, run.started_at DESC NULLS LAST, run.run_id DESC
)
SELECT target.priority_tier,
       target.canonical_name,
       site.source_type,
       site.site_id,
       latest.raw_job_count,
       latest.target_job_count,
       latest.review_job_count,
       round(100.0 * COALESCE(latest.review_job_count, 0) / NULLIF(latest.raw_job_count, 0), 1) AS review_pct,
       site.site_url
FROM latest
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.verification_status = 'verified'
  AND site.crawl_enabled
  AND (
       COALESCE(latest.raw_job_count, 0) >= 700
       OR COALESCE(latest.review_job_count, 0) >= 150
       OR (
           COALESCE(latest.raw_job_count, 0) >= 100
           AND COALESCE(latest.review_job_count, 0) >= COALESCE(latest.target_job_count, 0) * 2
       )
  )
ORDER BY latest.raw_job_count DESC NULLS LAST, latest.review_job_count DESC NULLS LAST
LIMIT 80;

\echo '=== Remaining generic platform-like candidates (company-level boards only) ==='
WITH best_generic AS (
    SELECT DISTINCT ON (target.consolidation_key)
           target.consolidation_key,
           target.canonical_name,
           target.priority_tier,
           target.priority_score,
           site.site_id,
           site.site_url,
           site.normalized_domain,
           COALESCE(site.candidate_score, 0) AS candidate_score
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
    ORDER BY target.consolidation_key,
             site.candidate_score DESC NULLS LAST,
             site.candidate_rank NULLS LAST,
             site.site_id
), platform AS (
    SELECT *,
           CASE
             WHEN normalized_domain LIKE '%.adp.com' OR normalized_domain = 'workforcenow.adp.com' THEN 'adp'
             WHEN normalized_domain LIKE '%.paycomonline.net' OR normalized_domain = 'paycomonline.net' THEN 'paycom'
             WHEN normalized_domain LIKE '%.paycor.com' OR normalized_domain = 'recruiting.paycor.com' THEN 'paycor'
             WHEN normalized_domain LIKE '%.applicantpro.com' OR normalized_domain = 'applicantpro.com' THEN 'applicantpro'
             WHEN normalized_domain LIKE '%.applytojob.com' OR normalized_domain = 'applytojob.com' THEN 'applytojob'
             WHEN normalized_domain LIKE '%.hrmdirect.com' OR normalized_domain = 'hrmdirect.com' THEN 'hrmdirect'
             WHEN normalized_domain LIKE '%.jazz.co' OR normalized_domain = 'jazz.co' THEN 'jazz'
             WHEN normalized_domain LIKE '%.crelate.com' OR normalized_domain = 'jobs.crelate.com' THEN 'crelate'
             WHEN normalized_domain LIKE '%.talentnest.com' OR normalized_domain = 'talentnest.com' THEN 'talentnest'
             WHEN normalized_domain LIKE '%.hireology.com' OR normalized_domain = 'hireology.com' THEN 'hireology'
             WHEN normalized_domain LIKE '%.catsone.com' OR normalized_domain = 'catsone.com' THEN 'catsone'
             WHEN normalized_domain LIKE '%.breezy.hr' OR normalized_domain = 'breezy.hr' THEN 'breezy'
             WHEN normalized_domain LIKE '%.trakstar.com' OR normalized_domain = 'trakstar.com' THEN 'trakstar'
             WHEN normalized_domain = 'app.dover.com' THEN 'dover'
             WHEN normalized_domain = 'jobscore.com' OR normalized_domain LIKE '%.jobscore.com' THEN 'jobscore'
           END AS platform_name
    FROM best_generic
)
SELECT platform_name,
       normalized_domain,
       COUNT(*) AS companies,
       string_agg(DISTINCT priority_tier, ', ' ORDER BY priority_tier) AS tiers,
       max(priority_score) AS max_priority_score,
       max(candidate_score) AS max_candidate_score,
       min(site_url) AS example_url
FROM platform
WHERE platform_name IS NOT NULL
GROUP BY 1, 2
ORDER BY companies DESC, max_priority_score DESC, max_candidate_score DESC
LIMIT 80;

\echo '=== Samples for remaining platform-like candidates ==='
WITH best_generic AS (
    SELECT DISTINCT ON (target.consolidation_key)
           target.consolidation_key,
           target.canonical_name,
           target.priority_tier,
           target.priority_score,
           site.site_id,
           site.site_url,
           site.normalized_domain,
           COALESCE(site.candidate_score, 0) AS candidate_score
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
    ORDER BY target.consolidation_key,
             site.candidate_score DESC NULLS LAST,
             site.candidate_rank NULLS LAST,
             site.site_id
), platform AS (
    SELECT *,
           CASE
             WHEN normalized_domain LIKE '%.adp.com' OR normalized_domain = 'workforcenow.adp.com' THEN 'adp'
             WHEN normalized_domain LIKE '%.paycomonline.net' OR normalized_domain = 'paycomonline.net' THEN 'paycom'
             WHEN normalized_domain LIKE '%.paycor.com' OR normalized_domain = 'recruiting.paycor.com' THEN 'paycor'
             WHEN normalized_domain LIKE '%.applicantpro.com' OR normalized_domain = 'applicantpro.com' THEN 'applicantpro'
             WHEN normalized_domain LIKE '%.applytojob.com' OR normalized_domain = 'applytojob.com' THEN 'applytojob'
             WHEN normalized_domain LIKE '%.hrmdirect.com' OR normalized_domain = 'hrmdirect.com' THEN 'hrmdirect'
             WHEN normalized_domain LIKE '%.jazz.co' OR normalized_domain = 'jazz.co' THEN 'jazz'
             WHEN normalized_domain LIKE '%.crelate.com' OR normalized_domain = 'jobs.crelate.com' THEN 'crelate'
             WHEN normalized_domain LIKE '%.talentnest.com' OR normalized_domain = 'talentnest.com' THEN 'talentnest'
             WHEN normalized_domain LIKE '%.hireology.com' OR normalized_domain = 'hireology.com' THEN 'hireology'
             WHEN normalized_domain LIKE '%.catsone.com' OR normalized_domain = 'catsone.com' THEN 'catsone'
             WHEN normalized_domain LIKE '%.breezy.hr' OR normalized_domain = 'breezy.hr' THEN 'breezy'
             WHEN normalized_domain LIKE '%.trakstar.com' OR normalized_domain = 'trakstar.com' THEN 'trakstar'
             WHEN normalized_domain = 'app.dover.com' THEN 'dover'
             WHEN normalized_domain = 'jobscore.com' OR normalized_domain LIKE '%.jobscore.com' THEN 'jobscore'
           END AS platform_name
    FROM best_generic
), ranked AS (
    SELECT *,
           row_number() OVER (
               PARTITION BY platform_name
               ORDER BY priority_tier, priority_score DESC, candidate_score DESC, site_id
           ) AS rn
    FROM platform
    WHERE platform_name IS NOT NULL
)
SELECT platform_name,
       rn,
       priority_tier,
       priority_score,
       candidate_score,
       site_id,
       canonical_name,
       normalized_domain,
       site_url
FROM ranked
WHERE rn <= 5
ORDER BY platform_name, rn;
SQL
