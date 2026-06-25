\pset pager off

\echo '=== Current tier and zero-score distribution ==='
SELECT coalesce(crawl_priority_tier, 'OUT_OF_QUEUE') AS tier,
       count(*) AS companies,
       count(*) FILTER (WHERE priority_score = 0) AS zero_score
FROM jobpush.company_targets_consolidated
GROUP BY 1 ORDER BY 1;

\echo '=== 1-2 LCA, every title is clearly executive level ==='
WITH candidate_feins AS (
    SELECT fein, name, lca_count
    FROM public.companies
    WHERE lca_count BETWEEN 1 AND 2
), title_stats AS (
    SELECT
        company.fein,
        company.name,
        count(*) AS case_count,
        count(*) FILTER (WHERE lower(coalesce(lcase.job_title, '')) ~
          '(^|[^a-z])(ceo|cfo|coo|cto|cio|cmo|cro|chro|chief[[:space:]-]+([a-z]+[[:space:]-]+){0,4}officer|president|vice president|executive director|managing director|general manager|owner|founder)([^a-z]|$)'
        ) AS executive_case_count,
        array_agg(DISTINCT lcase.job_title ORDER BY lcase.job_title) AS titles
    FROM candidate_feins company
    JOIN public.lca_cases lcase ON lcase.employer_fein = company.fein
    GROUP BY company.fein, company.name
)
SELECT count(*) AS excluded_companies,
       count(*) FILTER (WHERE target.crawl_priority_tier IS NOT NULL) AS currently_in_queue,
       count(*) FILTER (WHERE target.crawl_priority_tier = 'P1') AS current_p1,
       count(*) FILTER (WHERE target.crawl_priority_tier = 'P2') AS current_p2
FROM title_stats stats
JOIN jobpush.company_targets_consolidated target
  ON stats.fein = ANY(target.member_feins)
WHERE stats.case_count BETWEEN 1 AND 2
  AND stats.executive_case_count = stats.case_count;

\echo '=== Crawl coverage for all enabled P0/P1/P2 companies ==='
WITH sites AS (
    SELECT consolidation_key,
           count(*) FILTER (WHERE verification_status = 'verified') AS verified_sites,
           count(*) FILTER (WHERE verification_status = 'verified' AND crawl_enabled) AS enabled_sites,
           count(*) FILTER (WHERE last_crawled_at IS NOT NULL) AS attempted_sites,
           count(*) FILTER (WHERE last_success_at IS NOT NULL) AS successful_sites,
           count(*) FILTER (WHERE crawl_status = 'failed') AS failed_sites
    FROM jobpush.career_sites
    GROUP BY consolidation_key
)
SELECT target.priority_tier,
       count(*) AS enabled_companies,
       count(*) FILTER (WHERE coalesce(sites.verified_sites, 0) > 0) AS with_verified_site,
       count(*) FILTER (WHERE coalesce(sites.enabled_sites, 0) > 0) AS with_enabled_site,
       count(*) FILTER (WHERE coalesce(sites.attempted_sites, 0) > 0) AS ever_attempted,
       count(*) FILTER (WHERE coalesce(sites.successful_sites, 0) > 0) AS ever_succeeded,
       count(*) FILTER (WHERE coalesce(sites.failed_sites, 0) > 0) AS currently_failed
FROM jobpush.crawl_targets target
LEFT JOIN sites USING (consolidation_key)
WHERE target.enabled
GROUP BY target.priority_tier
ORDER BY target.priority_tier;

\echo '=== Recent crawl runs by adapter and status ==='
SELECT site.source_type, run.status, count(*) AS runs,
       sum(run.parsed_job_count) AS parsed_jobs,
       sum(run.new_job_count) AS new_jobs,
       max(run.finished_at) AS latest_run
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
WHERE run.started_at >= now() - interval '48 hours'
GROUP BY site.source_type, run.status
ORDER BY site.source_type, run.status;
