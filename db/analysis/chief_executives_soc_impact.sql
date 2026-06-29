\pset pager off

\echo '=== Chief Executives in target_soc_roles ==='
SELECT normalized_soc_code, representative_title, active, source, updated_at
FROM jobpush.target_soc_roles
WHERE normalized_soc_code = '11101100'
   OR lower(representative_title) = 'chief executives'
ORDER BY normalized_soc_code;

\echo '=== active target SOC count ==='
SELECT COUNT(*) AS active_target_soc_roles
FROM jobpush.target_soc_roles
WHERE active;

\echo '=== LCA rows with Chief Executives SOC ==='
SELECT jobpush.normalize_soc_code(soc_code) AS normalized_soc_code,
       soc_title,
       count(*) AS lca_rows,
       count(DISTINCT employer_fein) AS employers
FROM public.lca_cases
WHERE jobpush.normalize_soc_code(soc_code) = '11101100'
   OR lower(soc_title) = 'chief executives'
GROUP BY 1, 2
ORDER BY lca_rows DESC;

\echo '=== currently enabled crawl targets whose only target-role evidence may be Chief Executives ==='
WITH all_units AS (
    SELECT member_row.group_id AS consolidation_key, member_row.fein
    FROM jobpush.company_consolidation_members member_row
    UNION ALL
    SELECT company_row.fein AS consolidation_key, company_row.fein
    FROM public.companies company_row
    WHERE NOT EXISTS (
        SELECT 1
        FROM jobpush.company_consolidation_members member_row
        WHERE member_row.fein = company_row.fein
    )
), chief_keys AS (
    SELECT DISTINCT unit.consolidation_key
    FROM public.lca_cases lca
    JOIN all_units unit
      ON unit.fein = lca.employer_fein
    WHERE jobpush.normalize_soc_code(lca.soc_code) = '11101100'
       OR lower(lca.soc_title) = 'chief executives'
), non_chief_target_keys AS (
    SELECT DISTINCT unit.consolidation_key
    FROM public.lca_cases lca
    JOIN all_units unit
      ON unit.fein = lca.employer_fein
    JOIN jobpush.target_soc_roles target
      ON target.active
     AND target.normalized_soc_code = jobpush.normalize_soc_code(lca.soc_code)
    WHERE jobpush.normalize_soc_code(lca.soc_code) <> '11101100'
)
SELECT target.priority_tier,
       count(*) AS companies
FROM jobpush.crawl_targets target
JOIN chief_keys USING (consolidation_key)
LEFT JOIN non_chief_target_keys other USING (consolidation_key)
WHERE target.enabled
  AND other.consolidation_key IS NULL
GROUP BY 1
ORDER BY 1;

\echo '=== details for any remaining enabled Chief-only crawl targets ==='
WITH all_units AS (
    SELECT member_row.group_id AS consolidation_key, member_row.fein
    FROM jobpush.company_consolidation_members member_row
    UNION ALL
    SELECT company_row.fein AS consolidation_key, company_row.fein
    FROM public.companies company_row
    WHERE NOT EXISTS (
        SELECT 1
        FROM jobpush.company_consolidation_members member_row
        WHERE member_row.fein = company_row.fein
    )
), chief_keys AS (
    SELECT DISTINCT unit.consolidation_key
    FROM public.lca_cases lca
    JOIN all_units unit
      ON unit.fein = lca.employer_fein
    WHERE jobpush.normalize_soc_code(lca.soc_code) = '11101100'
       OR lower(lca.soc_title) = 'chief executives'
), non_chief_target_keys AS (
    SELECT DISTINCT unit.consolidation_key
    FROM public.lca_cases lca
    JOIN all_units unit
      ON unit.fein = lca.employer_fein
    JOIN jobpush.target_soc_roles target
      ON target.active
     AND target.normalized_soc_code = jobpush.normalize_soc_code(lca.soc_code)
    WHERE jobpush.normalize_soc_code(lca.soc_code) <> '11101100'
)
SELECT target.consolidation_key, target.canonical_name, target.priority_tier,
       target.priority_score, consolidated.target_role_score,
       consolidated.target_role_lca_count, target.priority_source
FROM jobpush.crawl_targets target
JOIN jobpush.company_targets_consolidated consolidated USING (consolidation_key)
JOIN chief_keys USING (consolidation_key)
LEFT JOIN non_chief_target_keys other USING (consolidation_key)
WHERE target.enabled
  AND other.consolidation_key IS NULL
ORDER BY target.priority_tier, target.priority_score DESC, target.canonical_name
LIMIT 20;

\echo '=== current enabled crawl target tiers ==='
SELECT priority_tier, COUNT(*) AS companies
FROM jobpush.crawl_targets
WHERE enabled
GROUP BY priority_tier
ORDER BY priority_tier;
