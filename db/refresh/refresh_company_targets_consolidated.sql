BEGIN;

TRUNCATE jobpush.company_targets_consolidated;

WITH dataset_window AS (
    SELECT MAX(decision_date) AS max_decision_date
    FROM public.lca_cases
), merged_units AS (
    SELECT
        grp.group_id AS consolidation_key,
        grp.canonical_name,
        TRUE AS is_merged_group,
        grp.linkedin_employer_key,
        grp.member_fein_count,
        member_row.fein
    FROM jobpush.company_consolidation_groups grp
    JOIN jobpush.company_consolidation_members member_row
      ON member_row.group_id = grp.group_id
), singleton_units AS (
    SELECT
        company_row.fein AS consolidation_key,
        company_row.name AS canonical_name,
        FALSE AS is_merged_group,
        NULL::TEXT AS linkedin_employer_key,
        1 AS member_fein_count,
        company_row.fein
    FROM public.companies company_row
    WHERE NOT EXISTS (
        SELECT 1
        FROM jobpush.company_consolidation_members member_row
        WHERE member_row.fein = company_row.fein
    )
), all_units AS (
    SELECT * FROM merged_units
    UNION ALL
    SELECT * FROM singleton_units
), unit_meta AS (
    SELECT
        consolidation_key,
        MIN(canonical_name) AS canonical_name,
        BOOL_OR(is_merged_group) AS is_merged_group,
        MIN(linkedin_employer_key) AS linkedin_employer_key,
        MAX(member_fein_count) AS member_fein_count,
        ARRAY_AGG(DISTINCT fein ORDER BY fein) AS member_feins
    FROM all_units
    GROUP BY consolidation_key
), primary_member AS (
    SELECT DISTINCT ON (unit.consolidation_key)
        unit.consolidation_key,
        unit.fein AS primary_fein,
        company_row.city AS employer_city,
        company_row.state AS employer_state,
        company_row.naics_code,
        company_row.naics_sector
    FROM all_units unit
    JOIN public.companies company_row
      ON company_row.fein = unit.fein
    ORDER BY unit.consolidation_key, company_row.lca_count DESC, company_row.name
), company_stats AS (
    SELECT
        unit.consolidation_key,
        SUM(company_row.lca_count)::INTEGER AS lca_count,
        SUM(company_row.certified_count)::INTEGER AS certified_count
    FROM all_units unit
    JOIN public.companies company_row
      ON company_row.fein = unit.fein
    GROUP BY unit.consolidation_key
), filing_stats AS (
    SELECT
        unit.consolidation_key,
        COUNT(target.normalized_soc_code)::INTEGER AS target_role_lca_count,
        MAX(lcase.decision_date) AS last_decision_date
    FROM all_units unit
    JOIN public.lca_cases lcase
      ON lcase.employer_fein = unit.fein
    LEFT JOIN jobpush.target_soc_roles target
        ON target.active
       AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
    GROUP BY unit.consolidation_key
), product_role_stats AS (
    SELECT
        unit.consolidation_key,
        BOOL_OR(jobpush.is_product_role_job_title(lcase.job_title)) AS has_product_role_job,
        BOOL_OR(jobpush.is_product_manager_job_title(lcase.job_title)) AS has_product_manager_job,
        COUNT(*) FILTER (
            WHERE jobpush.is_product_role_job_title(lcase.job_title)
        )::INTEGER AS product_role_lca_count
    FROM all_units unit
    JOIN public.lca_cases lcase
      ON lcase.employer_fein = unit.fein
    GROUP BY unit.consolidation_key
), source_base AS (
    SELECT
        meta.consolidation_key,
        meta.canonical_name,
        meta.is_merged_group,
        meta.linkedin_employer_key,
        meta.member_fein_count,
        meta.member_feins,
        primary_row.primary_fein,
        primary_row.employer_city,
        primary_row.employer_state,
        primary_row.naics_code,
        primary_row.naics_sector,
        company_row.lca_count,
        company_row.certified_count,
        (company_row.lca_count = 1) AS single_lca_company,
        COALESCE(filing_row.target_role_lca_count, 0) AS target_role_lca_count,
        COALESCE(product_row.has_product_role_job, FALSE) AS has_product_role_job,
        COALESCE(product_row.has_product_manager_job, FALSE) AS has_product_manager_job,
        COALESCE(product_row.product_role_lca_count, 0) AS product_role_lca_count,
        ROUND(
            100.0 * COALESCE(product_row.product_role_lca_count, 0)
                / NULLIF(company_row.lca_count, 0),
            2
        ) AS product_role_lca_pct,
        filing_row.last_decision_date,
        COALESCE(
            filing_row.last_decision_date >= window_row.max_decision_date - 365,
            FALSE
        ) AS recent_lca,
        EXISTS (
            SELECT 1
            FROM all_units unit
            JOIN public.companies company_check
              ON company_check.fein = unit.fein
            WHERE unit.consolidation_key = meta.consolidation_key
              AND jobpush.is_chicago_metro(company_check.city, company_check.state)
        ) AS has_chicago_member,
        EXISTS (
            SELECT 1
            FROM all_units unit
            WHERE unit.consolidation_key = meta.consolidation_key
              AND jobpush.is_linkedin_top_employer_2026(unit.fein)
        ) AS has_linkedin_member
    FROM unit_meta meta
    JOIN company_stats company_row
      ON company_row.consolidation_key = meta.consolidation_key
    JOIN primary_member primary_row
      ON primary_row.consolidation_key = meta.consolidation_key
    LEFT JOIN filing_stats filing_row
      ON filing_row.consolidation_key = meta.consolidation_key
    LEFT JOIN product_role_stats product_row
      ON product_row.consolidation_key = meta.consolidation_key
    CROSS JOIN dataset_window window_row
), scored AS (
    SELECT
        source_base.*,
        CASE WHEN target_role_lca_count > 0 THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS target_role_score,
        CASE WHEN target_role_lca_count > 0 AND lca_count > 1 THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS lca_count_score,
        CASE WHEN target_role_lca_count > 0 AND has_chicago_member
            THEN 0.5::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS chicago_score,
        CASE WHEN target_role_lca_count > 0 AND has_product_role_job
            THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS product_role_score,
        CASE WHEN target_role_lca_count > 0 AND has_product_manager_job
            THEN 0.25::NUMERIC(4, 2) ELSE 0::NUMERIC(4, 2) END
            AS product_manager_score,
        CASE WHEN has_linkedin_member OR linkedin_employer_key IS NOT NULL
            THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS linkedin_top_employer_score
    FROM source_base
), totaled AS (
    SELECT
        scored.*,
        (
            target_role_score + lca_count_score + chicago_score
            + product_role_score + product_manager_score
            + linkedin_top_employer_score
        )::NUMERIC(4, 2) AS priority_score
    FROM scored
)
INSERT INTO jobpush.company_targets_consolidated (
    consolidation_key, canonical_name, is_merged_group, linkedin_employer_key,
    member_fein_count, member_feins, primary_fein,
    employer_city, employer_state, naics_code, naics_sector,
    lca_count, certified_count, single_lca_company, target_role_lca_count,
    product_role_lca_count, product_role_lca_pct,
    last_decision_date, recent_lca,
    target_role_score, lca_count_score, chicago_score,
    product_role_score, product_manager_score, linkedin_top_employer_score,
    priority_score, priority_version, updated_at
)
SELECT
    consolidation_key, canonical_name, is_merged_group, linkedin_employer_key,
    member_fein_count, member_feins, primary_fein,
    employer_city, employer_state, naics_code, naics_sector,
    lca_count, certified_count, single_lca_company, target_role_lca_count,
    product_role_lca_count, product_role_lca_pct,
    last_decision_date, recent_lca,
    target_role_score, lca_count_score, chicago_score,
    product_role_score, product_manager_score, linkedin_top_employer_score,
    priority_score, 'priority-v7-consolidated', now()
FROM totaled
ON CONFLICT (consolidation_key) DO UPDATE SET
    canonical_name = EXCLUDED.canonical_name,
    is_merged_group = EXCLUDED.is_merged_group,
    linkedin_employer_key = EXCLUDED.linkedin_employer_key,
    member_fein_count = EXCLUDED.member_fein_count,
    member_feins = EXCLUDED.member_feins,
    primary_fein = EXCLUDED.primary_fein,
    employer_city = EXCLUDED.employer_city,
    employer_state = EXCLUDED.employer_state,
    naics_code = EXCLUDED.naics_code,
    naics_sector = EXCLUDED.naics_sector,
    lca_count = EXCLUDED.lca_count,
    certified_count = EXCLUDED.certified_count,
    single_lca_company = EXCLUDED.single_lca_company,
    target_role_lca_count = EXCLUDED.target_role_lca_count,
    product_role_lca_count = EXCLUDED.product_role_lca_count,
    product_role_lca_pct = EXCLUDED.product_role_lca_pct,
    last_decision_date = EXCLUDED.last_decision_date,
    recent_lca = EXCLUDED.recent_lca,
    target_role_score = EXCLUDED.target_role_score,
    lca_count_score = EXCLUDED.lca_count_score,
    chicago_score = EXCLUDED.chicago_score,
    product_role_score = EXCLUDED.product_role_score,
    product_manager_score = EXCLUDED.product_manager_score,
    linkedin_top_employer_score = EXCLUDED.linkedin_top_employer_score,
    priority_score = EXCLUDED.priority_score,
    priority_version = EXCLUDED.priority_version,
    updated_at = now();

COMMIT;
