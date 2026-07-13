\pset pager off

CREATE TEMP TABLE tmp_tavily_blockers AS
WITH tavily_searched AS (
    SELECT DISTINCT consolidation_key
    FROM jobpush.career_site_discovery_attempts
    WHERE search_succeeded
),
targets AS (
    SELECT target.consolidation_key, target.priority_tier
    FROM jobpush.crawl_targets target
    JOIN tavily_searched ts USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P2', 'P3')
),
sites AS (
    SELECT
        site.consolidation_key,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled) AS has_enabled,
        count(*) FILTER (WHERE site.verification_status = 'unverified') AS unverified_n,
        count(*) FILTER (WHERE site.verification_status = 'unverified'
                           AND site.source_type = 'generic_html') AS generic_unverified_n,
        count(*) FILTER (WHERE site.verification_status = 'unverified'
                           AND site.source_type <> 'generic_html') AS structured_unverified_n,
        count(*) FILTER (
            WHERE site.verification_status = 'unverified'
              AND site.source_type = 'generic_html'
              AND coalesce(site.last_error, '') LIKE 'generic_jsonld_checked:%'
        ) AS generic_jsonld_checked_n,
        count(*) FILTER (
            WHERE site.verification_status = 'unverified'
              AND site.source_type IN (
                  'greenhouse','workday','lever','ashby','smartrecruiters','oracle_cloud',
                  'amazon_jobs','jobvite','paylocity','rippling','applytojob','catsone',
                  'trakstar','breezy','dover','ultipro','eightfold','cognizant_jobs','icims'
              )
        ) AS supported_structured_unverified_n,
        count(*) FILTER (
            WHERE site.verification_status = 'unverified'
              AND site.source_type IN (
                  'successfactors','brassring','comeet','trinethire','talentbrew',
                  'gusto','phenom','jobscore','applicantpro','unknown'
              )
        ) AS no_parser_or_blocked_n,
        count(*) FILTER (WHERE site.verification_status = 'rejected') AS rejected_n,
        (array_agg(site.source_type ORDER BY site.candidate_rank NULLS LAST,
                   site.candidate_score DESC NULLS LAST, site.site_id)
         FILTER (WHERE site.verification_status = 'unverified'))[1] AS rank1_source,
        (array_agg(left(site.site_url, 120) ORDER BY site.candidate_rank NULLS LAST,
                   site.candidate_score DESC NULLS LAST, site.site_id)
         FILTER (WHERE site.verification_status = 'unverified'))[1] AS rank1_url
    FROM jobpush.career_sites site
    JOIN targets t USING (consolidation_key)
    GROUP BY site.consolidation_key
)
SELECT
    t.priority_tier,
    CASE
        WHEN coalesce(s.has_enabled, FALSE) THEN '00_already_enabled'
        WHEN coalesce(s.unverified_n, 0) = 0 AND coalesce(s.rejected_n, 0) > 0
            THEN '01_only_rejected_candidates'
        WHEN coalesce(s.unverified_n, 0) = 0
            THEN '02_searched_but_no_candidate_rows'
        WHEN coalesce(s.generic_unverified_n, 0) > 0
             AND coalesce(s.structured_unverified_n, 0) = 0
             AND coalesce(s.generic_jsonld_checked_n, 0) > 0
            THEN '03_generic_only_no_jobposting_jsonld'
        WHEN coalesce(s.generic_unverified_n, 0) > 0
             AND coalesce(s.structured_unverified_n, 0) = 0
            THEN '04_generic_only_not_yet_jsonld_checked'
        WHEN coalesce(s.supported_structured_unverified_n, 0) > 0
             AND s.rank1_source = 'icims'
            THEN '05_icims_gated_timeout_or_bad_url'
        WHEN coalesce(s.supported_structured_unverified_n, 0) > 0
            THEN '06_supported_ats_but_bad_url_shape'
        WHEN coalesce(s.no_parser_or_blocked_n, 0) > 0
             AND s.rank1_source = 'gusto'
            THEN '07_gusto_aws_cloudflare_blocked'
        WHEN coalesce(s.no_parser_or_blocked_n, 0) > 0
            THEN '08_ats_identified_but_no_parser'
        WHEN coalesce(s.structured_unverified_n, 0) > 0
            THEN '09_other_structured_unverified'
        ELSE '10_other'
    END AS blocker,
    s.rank1_source,
    s.rank1_url
FROM targets t
LEFT JOIN sites s USING (consolidation_key);

\echo '=== Overall: Tavily-searched P2/P3 ==='
SELECT priority_tier,
       count(*) AS companies,
       count(*) FILTER (WHERE blocker = '00_already_enabled') AS enabled,
       count(*) FILTER (WHERE blocker <> '00_already_enabled') AS not_enabled
FROM tmp_tavily_blockers
GROUP BY priority_tier
ORDER BY priority_tier;

\echo '=== Primary blocker for NOT-enabled ==='
SELECT priority_tier, blocker, count(*) AS companies,
       round(100.0 * count(*) / nullif(sum(count(*)) OVER (PARTITION BY priority_tier), 0), 1) AS pct_of_not_enabled
FROM tmp_tavily_blockers
WHERE blocker <> '00_already_enabled'
GROUP BY priority_tier, blocker
ORDER BY priority_tier, companies DESC;

\echo '=== Combined P2+P3 not-enabled share ==='
SELECT blocker, count(*) AS companies,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM tmp_tavily_blockers
WHERE blocker <> '00_already_enabled'
GROUP BY blocker
ORDER BY companies DESC;

\echo '=== Rank-1 ATS inside no-parser / gusto buckets ==='
SELECT priority_tier, coalesce(rank1_source,'(none)') AS rank1_source, count(*) AS companies
FROM tmp_tavily_blockers
WHERE blocker IN ('07_gusto_aws_cloudflare_blocked','08_ats_identified_but_no_parser','09_other_structured_unverified')
GROUP BY 1,2
ORDER BY 1, companies DESC;

\echo '=== Sample: supported ATS bad URL shape ==='
SELECT priority_tier, rank1_source, rank1_url
FROM tmp_tavily_blockers
WHERE blocker = '06_supported_ats_but_bad_url_shape'
ORDER BY priority_tier, rank1_source
LIMIT 20;

\echo '=== Sample: only rejected ==='
SELECT priority_tier, count(*) AS companies
FROM tmp_tavily_blockers
WHERE blocker = '01_only_rejected_candidates'
GROUP BY 1;
