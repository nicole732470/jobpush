\echo '=== Two-filing target companies: strict high-seniority composition ==='
WITH impact AS (
    SELECT
        target.consolidation_key,
        target.canonical_name,
        target.priority_score,
        target.crawl_priority_tier,
        count(*) FILTER (
            WHERE lower(lca.job_title) ~
                '(^|[^a-z])(ceo|chief|president|vice president|vp|director|head|executive|managing director|senior manager|principal)([^a-z]|$)'
        ) AS high_seniority_rows
    FROM jobpush.company_targets_consolidated target
    JOIN public.lca_cases lca
      ON lca.employer_fein = ANY(target.member_feins)
    WHERE target.target_role_score = 1
      AND target.lca_count = 2
    GROUP BY 1,2,3,4
)
SELECT high_seniority_rows,
       count(*) AS companies,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM impact
GROUP BY high_seniority_rows
ORDER BY high_seniority_rows;

\echo '=== Both filings high-seniority, by current tier ==='
WITH impact AS (
    SELECT target.consolidation_key, target.crawl_priority_tier,
           count(*) FILTER (
               WHERE lower(lca.job_title) ~
                   '(^|[^a-z])(ceo|chief|president|vice president|vp|director|head|executive|managing director|senior manager|principal)([^a-z]|$)'
           ) AS high_seniority_rows
    FROM jobpush.company_targets_consolidated target
    JOIN public.lca_cases lca
      ON lca.employer_fein = ANY(target.member_feins)
    WHERE target.target_role_score = 1 AND target.lca_count = 2
    GROUP BY 1,2
)
SELECT crawl_priority_tier, count(*) AS companies
FROM impact
WHERE high_seniority_rows = 2
GROUP BY crawl_priority_tier
ORDER BY crawl_priority_tier;
