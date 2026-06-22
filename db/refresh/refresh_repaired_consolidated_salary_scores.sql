-- Deprecated: prefer refresh_employer_filing_stats.sql + refresh_company_targets_consolidated.sql
-- Kept for reference; wage repair (018) now uses the full optimized pipeline.

BEGIN;

WITH fein_units AS (
    SELECT member.fein, member.group_id AS consolidation_key
    FROM jobpush.company_consolidation_members member
    UNION ALL
    SELECT company.fein, company.fein AS consolidation_key
    FROM public.companies company
    WHERE NOT EXISTS (
        SELECT 1
        FROM jobpush.company_consolidation_members member
        WHERE member.fein = company.fein
    )
), affected_units AS (
    SELECT DISTINCT unit.consolidation_key
    FROM jobpush.lca_wage_repair_backup backup
    JOIN public.lca_cases lcase
      ON lcase.lca_case_id = backup.lca_case_id
    JOIN fein_units unit
      ON unit.fein = lcase.employer_fein
    WHERE backup.repair_batch = 'fy2025-q1-official'
), affected_members AS (
    SELECT unit.fein, unit.consolidation_key
    FROM fein_units unit
    JOIN affected_units affected
      ON affected.consolidation_key = unit.consolidation_key
), target_salary_rows AS (
    SELECT
        member.consolidation_key,
        CASE
            WHEN target.normalized_soc_code IS NULL THEN NULL
            WHEN lcase.wage_rate_of_pay_from IS NULL THEN NULL
            WHEN lcase.wage_unit_of_pay = 'Year' THEN lcase.wage_rate_of_pay_from
            WHEN lcase.wage_unit_of_pay = 'Month' THEN lcase.wage_rate_of_pay_from * 12
            WHEN lcase.wage_unit_of_pay = 'Bi-Weekly' THEN lcase.wage_rate_of_pay_from * 26
            WHEN lcase.wage_unit_of_pay = 'Week' THEN lcase.wage_rate_of_pay_from * 52
            WHEN lcase.wage_unit_of_pay = 'Hour' THEN lcase.wage_rate_of_pay_from * 2080
            ELSE NULL
        END AS annual_salary,
        target.normalized_soc_code
    FROM affected_members member
    JOIN public.lca_cases lcase
      ON lcase.employer_fein = member.fein
    LEFT JOIN jobpush.target_soc_roles target
      ON target.active
     AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
), salary_stats AS (
    SELECT
        consolidation_key,
        COUNT(normalized_soc_code)::INTEGER AS target_role_lca_count,
        MIN(annual_salary)::NUMERIC(14, 2) AS min_annual_salary,
        COUNT(*) FILTER (
            WHERE normalized_soc_code IS NOT NULL AND annual_salary IS NOT NULL
        )::INTEGER AS valid_salary_count,
        COUNT(*) FILTER (
            WHERE normalized_soc_code IS NOT NULL AND annual_salary IS NULL
        )::INTEGER AS invalid_salary_count
    FROM target_salary_rows
    GROUP BY consolidation_key
), new_scores AS (
    SELECT
        target.consolidation_key,
        stats.target_role_lca_count,
        stats.min_annual_salary,
        stats.valid_salary_count,
        stats.invalid_salary_count,
        CASE
            WHEN stats.target_role_lca_count > 0 AND stats.min_annual_salary >= 90000
                THEN 1::NUMERIC(3, 1)
            ELSE 0::NUMERIC(3, 1)
        END AS new_salary_score
    FROM jobpush.company_targets_consolidated target
    JOIN salary_stats stats
      ON stats.consolidation_key = target.consolidation_key
)
UPDATE jobpush.company_targets_consolidated target
SET
    target_role_lca_count = score.target_role_lca_count,
    target_role_min_annual_salary = score.min_annual_salary,
    target_role_valid_salary_lca_count = score.valid_salary_count,
    target_role_invalid_salary_lca_count = score.invalid_salary_count,
    salary_score = score.new_salary_score,
    priority_score = target.priority_score - target.salary_score + score.new_salary_score,
    updated_at = now()
FROM new_scores score
WHERE score.consolidation_key = target.consolidation_key;

COMMIT;
