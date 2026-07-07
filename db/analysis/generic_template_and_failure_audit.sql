\pset pager off

\echo '=== Remaining generic candidates by tier ==='
WITH best_generic AS (
    SELECT DISTINCT ON (target.consolidation_key)
        target.consolidation_key,
        target.canonical_name,
        target.priority_tier,
        target.priority_score,
        site.site_id,
        site.site_url,
        site.normalized_domain,
        COALESCE(site.candidate_score, 0) AS candidate_score,
        COALESCE(site.last_error, '') AS last_error
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
), classified AS (
    SELECT *,
           CASE
               WHEN normalized_domain ~* '(^|\.)(h1bvisajobs|justia\.jobs|careersinfood|selectleaders|directlyapply|remotive|purpose\.jobs|employbl|edtechjobs|milwaukeejobs|usnlx|jsfirm|nbmbaa|jobs-redefined)\.' THEN 'external_job_board_or_aggregator'
               WHEN normalized_domain ~* '(greenhouse|lever|ashbyhq|smartrecruiters|icims|myworkdayjobs|oraclecloud|workday|jobvite|workable|paylocity|rippling|ultipro|trinethire|comeet|successfactors|phenom|talentbrew|brassring)' THEN 'known_ats_or_platform_missed'
               WHEN normalized_domain ~* '^(careers|jobs)\.' THEN 'careers_jobs_subdomain'
               WHEN site_url ~* '/job-search|/search-jobs|/search/jobs|/open-positions|/openings|/opportunities' THEN 'job_search_template'
               WHEN site_url ~* '/careers?|/locale/careers?|/about-us/careers?' THEN 'corporate_careers_path'
               WHEN site_url ~* '/jobs?' THEN 'corporate_jobs_path'
               WHEN site_url ~* '^https?://[^/]+/?$' THEN 'homepage_or_root'
               ELSE 'other_generic_page'
           END AS template_family
    FROM best_generic
)
SELECT priority_tier,
       template_family,
       count(*) AS companies,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY priority_tier), 2) AS pct_in_tier,
       round(avg(candidate_score), 2) AS avg_candidate_score,
       max(priority_score) AS max_priority_score
FROM classified
GROUP BY priority_tier, template_family
ORDER BY priority_tier, companies DESC;

\echo '=== Top repeatable generic domains/templates ==='
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
), classified AS (
    SELECT *,
           CASE
               WHEN normalized_domain ~* '(^|\.)(h1bvisajobs|justia\.jobs|careersinfood|selectleaders|directlyapply|remotive|purpose\.jobs|employbl|edtechjobs|milwaukeejobs|usnlx|jsfirm|nbmbaa|jobs-redefined)\.' THEN 'external_job_board_or_aggregator'
               WHEN normalized_domain ~* '(greenhouse|lever|ashbyhq|smartrecruiters|icims|myworkdayjobs|oraclecloud|workday|jobvite|workable|paylocity|rippling|ultipro|trinethire|comeet|successfactors|phenom|talentbrew|brassring)' THEN 'known_ats_or_platform_missed'
               WHEN normalized_domain ~* '^(careers|jobs)\.' THEN 'careers_jobs_subdomain'
               WHEN site_url ~* '/job-search|/search-jobs|/search/jobs|/open-positions|/openings|/opportunities' THEN 'job_search_template'
               WHEN site_url ~* '/careers?|/locale/careers?|/about-us/careers?' THEN 'corporate_careers_path'
               WHEN site_url ~* '/jobs?' THEN 'corporate_jobs_path'
               WHEN site_url ~* '^https?://[^/]+/?$' THEN 'homepage_or_root'
               ELSE 'other_generic_page'
           END AS template_family
    FROM best_generic
)
SELECT template_family,
       normalized_domain,
       count(*) AS companies,
       string_agg(DISTINCT priority_tier, ', ' ORDER BY priority_tier) AS tiers,
       max(priority_score) AS max_priority_score,
       max(candidate_score) AS max_candidate_score,
       min(site_url) AS example_url,
       string_agg(canonical_name, '; ' ORDER BY priority_score DESC, canonical_name) AS example_companies
FROM classified
WHERE template_family <> 'external_job_board_or_aggregator'
GROUP BY template_family, normalized_domain
HAVING count(*) >= 3
ORDER BY companies DESC, max_priority_score DESC, max_candidate_score DESC
LIMIT 80;

\echo '=== External/aggregator generic candidates to reject or deprioritize ==='
WITH best_generic AS (
    SELECT DISTINCT ON (target.consolidation_key)
        target.consolidation_key,
        target.canonical_name,
        target.priority_tier,
        target.priority_score,
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
)
SELECT normalized_domain,
       count(*) AS companies,
       string_agg(DISTINCT priority_tier, ', ' ORDER BY priority_tier) AS tiers,
       max(candidate_score) AS max_candidate_score,
       min(site_url) AS example_url
FROM best_generic
WHERE normalized_domain ~* '(^|\.)(h1bvisajobs|justia\.jobs|careersinfood|selectleaders|directlyapply|remotive|purpose\.jobs|employbl|edtechjobs|milwaukeejobs|usnlx|jsfirm|nbmbaa|jobs-redefined)\.'
GROUP BY normalized_domain
ORDER BY companies DESC, max_candidate_score DESC
LIMIT 40;

\echo '=== Current failed enabled sites by reason ==='
WITH latest_run AS (
    SELECT DISTINCT ON (run.site_id)
           run.site_id,
           run.status,
           run.error_code,
           COALESCE(run.error_message, '') AS error_message,
           run.started_at,
           run.finished_at
    FROM jobpush.crawl_runs run
    ORDER BY run.site_id, run.started_at DESC NULLS LAST, run.run_id DESC
), failed AS (
    SELECT target.priority_tier,
           target.canonical_name,
           site.site_id,
           site.source_type,
           site.site_url,
           site.crawl_status,
           COALESCE(NULLIF(site.last_error, ''), latest_run.error_message, '') AS error_text,
           latest_run.error_code
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    LEFT JOIN latest_run USING (site_id)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
), classified AS (
    SELECT *,
           CASE
               WHEN error_text ~* '404|not found' THEN 'wrong_or_stale_url_404'
               WHEN error_text ~* '403|forbidden' THEN 'blocked_403'
               WHEN error_text ~* 'timed out|timeout|read operation timed out' THEN 'timeout'
               WHEN error_text ~* 'unsupported source_type|No verified .* site' THEN 'runner_or_config_gap'
               WHEN error_text ~* 'JSONDecodeError|Expecting value|invalid json' THEN 'adapter_payload_parse'
               WHEN error_text ~* 'HTTP Error 5|502|503|504' THEN 'remote_5xx'
               ELSE 'adapter_exception_other'
           END AS failure_reason
    FROM failed
)
SELECT priority_tier,
       source_type,
       failure_reason,
       count(*) AS sites,
       string_agg(canonical_name || ' [' || left(regexp_replace(error_text, '\s+', ' ', 'g'), 80) || ']', '; ' ORDER BY canonical_name) AS examples
FROM classified
GROUP BY priority_tier, source_type, failure_reason
ORDER BY priority_tier, sites DESC, source_type, failure_reason;

