\pset pager off

\echo '=== P1 generic blocker domain clustering ==='
WITH site_rollup AS (
    SELECT
        site.consolidation_key,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled) AS has_enabled_site,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.last_success_at IS NOT NULL) AS has_success
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
), generic_sites AS (
    SELECT
        target.consolidation_key,
        target.canonical_name,
        target.priority_tier,
        target.priority_score,
        site.site_id,
        site.site_url,
        lower(regexp_replace(coalesce(site.normalized_domain, split_part(regexp_replace(site.site_url, '^https?://', ''), '/', 1)), '^www\.', '')) AS host,
        lower(regexp_replace(regexp_replace(site.site_url, '^https?://[^/]+', ''), '[?#].*$', '')) AS path,
        site.discovery_source,
        site.candidate_score,
        site.last_error
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    LEFT JOIN site_rollup rollup USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT coalesce(rollup.has_enabled_site, FALSE)
      AND NOT coalesce(rollup.has_success, FALSE)
), classified AS (
    SELECT *,
        CASE
            WHEN host LIKE '%myworkdayjobs.com' THEN 'workday_domain_missed'
            WHEN host LIKE '%greenhouse.io' THEN 'greenhouse_domain_missed'
            WHEN host LIKE '%lever.co' THEN 'lever_domain_missed'
            WHEN host LIKE '%ashbyhq.com' THEN 'ashby_domain_missed'
            WHEN host LIKE '%smartrecruiters.com' THEN 'smartrecruiters_domain_missed'
            WHEN host LIKE '%icims.com' THEN 'icims_domain_missed'
            WHEN host LIKE '%successfactors.%' OR host LIKE '%successfactors.com' THEN 'successfactors_domain_missed'
            WHEN host LIKE '%oraclecloud.com' OR host LIKE '%oraclecloud.com%' THEN 'oracle_cloud_domain_missed'
            WHEN path ~ '(career|careers|job|jobs|openings|opportunities)' THEN 'corporate_careers_page'
            ELSE 'generic_or_corporate_page'
        END AS template_family,
        CASE
            WHEN path ~ '^/?$' THEN '/'
            WHEN path ~ '^/(en-us|en|us)/(career|careers|jobs)(/|$)' THEN '/locale/careers'
            WHEN path ~ '^/(career|careers)(/|$)' THEN '/careers'
            WHEN path ~ '^/(job|jobs)(/|$)' THEN '/jobs'
            WHEN path ~ '^/(join-us|join|work-with-us)(/|$)' THEN '/join'
            WHEN path ~ '^/(about|company)(/|$)' THEN '/about'
            ELSE regexp_replace(path, '/[0-9]+', '/:id', 'g')
        END AS path_pattern
    FROM generic_sites
)
SELECT template_family,
       host,
       path_pattern,
       count(DISTINCT consolidation_key) AS companies,
       count(*) AS site_rows,
       round(avg(candidate_score)::numeric, 2) AS avg_candidate_score,
       string_agg(DISTINCT canonical_name, ', ' ORDER BY canonical_name) FILTER (WHERE candidate_score >= 50) AS examples
FROM classified
GROUP BY template_family, host, path_pattern
ORDER BY companies DESC, site_rows DESC, avg_candidate_score DESC NULLS LAST
LIMIT 80;

\echo '=== P1 generic blocker template family summary ==='
WITH site_rollup AS (
    SELECT
        site.consolidation_key,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled) AS has_enabled_site,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.last_success_at IS NOT NULL) AS has_success
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
), generic_sites AS (
    SELECT
        target.consolidation_key,
        lower(regexp_replace(coalesce(site.normalized_domain, split_part(regexp_replace(site.site_url, '^https?://', ''), '/', 1)), '^www\.', '')) AS host,
        lower(regexp_replace(regexp_replace(site.site_url, '^https?://[^/]+', ''), '[?#].*$', '')) AS path
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    LEFT JOIN site_rollup rollup USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT coalesce(rollup.has_enabled_site, FALSE)
      AND NOT coalesce(rollup.has_success, FALSE)
), classified AS (
    SELECT *,
        CASE
            WHEN host LIKE '%myworkdayjobs.com' THEN 'workday_domain_missed'
            WHEN host LIKE '%greenhouse.io' THEN 'greenhouse_domain_missed'
            WHEN host LIKE '%lever.co' THEN 'lever_domain_missed'
            WHEN host LIKE '%ashbyhq.com' THEN 'ashby_domain_missed'
            WHEN host LIKE '%smartrecruiters.com' THEN 'smartrecruiters_domain_missed'
            WHEN host LIKE '%icims.com' THEN 'icims_domain_missed'
            WHEN host LIKE '%successfactors.%' OR host LIKE '%successfactors.com' THEN 'successfactors_domain_missed'
            WHEN host LIKE '%oraclecloud.com' OR host LIKE '%oraclecloud.com%' THEN 'oracle_cloud_domain_missed'
            WHEN path ~ '(career|careers|job|jobs|openings|opportunities)' THEN 'corporate_careers_page'
            ELSE 'generic_or_corporate_page'
        END AS template_family
    FROM generic_sites
)
SELECT template_family,
       count(DISTINCT consolidation_key) AS companies,
       round(100.0 * count(DISTINCT consolidation_key) / nullif(sum(count(DISTINCT consolidation_key)) OVER (), 0), 2) AS pct_companies,
       count(*) AS site_rows
FROM classified
GROUP BY template_family
ORDER BY companies DESC;

\echo '=== Current failed enabled crawl sites ==='
WITH failed_sites AS (
    SELECT
        target.priority_tier,
        target.canonical_name,
        target.priority_score,
        site.site_id,
        site.source_type,
        site.site_url,
        site.last_error,
        site.last_crawled_at,
        CASE
            WHEN coalesce(site.last_error, '') ILIKE '%404%' THEN 'wrong_or_stale_ats_url'
            WHEN coalesce(site.last_error, '') ILIKE '%429%' OR coalesce(site.last_error, '') ILIKE '%rate%' THEN 'rate_limited'
            WHEN coalesce(site.last_error, '') ILIKE '%timeout%' OR coalesce(site.last_error, '') ILIKE '%timed out%' THEN 'timeout'
            WHEN coalesce(site.last_error, '') ILIKE '%403%' OR coalesce(site.last_error, '') ILIKE '%forbidden%' THEN 'blocked_or_forbidden'
            WHEN coalesce(site.last_error, '') ILIKE '%empty%' OR coalesce(site.last_error, '') ILIKE '%missing title%' THEN 'empty_or_malformed_payload'
            WHEN coalesce(site.last_error, '') ILIKE '%workday%' OR coalesce(site.last_error, '') ILIKE '%422%' THEN 'adapter_endpoint_or_payload'
            WHEN coalesce(site.last_error, '') = '' THEN 'unknown'
            ELSE 'other'
        END AS failure_reason
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2')
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
)
SELECT priority_tier,
       source_type,
       failure_reason,
       count(*) AS failed_sites,
       string_agg(canonical_name || ' [' || left(coalesce(last_error, ''), 120) || ']', E'\n' ORDER BY priority_score DESC NULLS LAST, canonical_name) AS examples
FROM failed_sites
GROUP BY priority_tier, source_type, failure_reason
ORDER BY failed_sites DESC, priority_tier, source_type, failure_reason;
