\echo '=== Google consolidated salary stats ==='
SELECT consolidation_key, canonical_name, target_role_min_annual_salary,
       target_role_valid_salary_lca_count, salary_score
FROM jobpush.company_targets_consolidated
WHERE consolidation_key IN ('google', 'alphabet-google');

\echo '=== Target-role filings under $90k (lowest first, last 3 years) ==='
WITH google_feins AS (
    SELECT unnest(member_feins) AS fein
    FROM jobpush.company_targets_consolidated
    WHERE consolidation_key IN ('google', 'alphabet-google')
    LIMIT 1
), enriched AS (
    SELECT
        c.name AS company_name,
        lcase.employer_fein,
        lcase.job_title,
        lcase.soc_code,
        target.representative_title AS soc_title,
        lcase.decision_date,
        lcase.wage_rate_of_pay_from,
        lcase.wage_unit_of_pay,
        jobpush.lca_annual_salary(
            lcase.wage_rate_of_pay_from,
            lcase.wage_unit_of_pay
        ) AS annual_salary
    FROM public.lca_cases lcase
    JOIN google_feins gf ON gf.fein = lcase.employer_fein
    JOIN public.companies c ON c.fein = lcase.employer_fein
    JOIN jobpush.target_soc_roles target
      ON target.active
     AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
    WHERE jobpush.lca_annual_salary(
            lcase.wage_rate_of_pay_from,
            lcase.wage_unit_of_pay
          ) IS NOT NULL
)
SELECT
    company_name,
    employer_fein,
    job_title,
    soc_code,
    soc_title,
    decision_date,
    wage_rate_of_pay_from,
    wage_unit_of_pay,
    annual_salary::numeric(12,2) AS annual_salary
FROM enriched
WHERE annual_salary < 90000
  AND decision_date >= (
      SELECT MAX(decision_date) - INTERVAL '3 years'
      FROM public.lca_cases
  )
ORDER BY annual_salary ASC, decision_date DESC
LIMIT 30;

\echo '=== Absolute minimum target-role salary (all time) ==='
WITH google_feins AS (
    SELECT unnest(member_feins) AS fein
    FROM jobpush.company_targets_consolidated
    WHERE consolidation_key IN ('google', 'alphabet-google')
    LIMIT 1
)
SELECT
    c.name AS company_name,
    lcase.job_title,
    lcase.soc_code,
    target.representative_title AS soc_title,
    lcase.decision_date,
    lcase.wage_rate_of_pay_from,
    lcase.wage_unit_of_pay,
    jobpush.lca_annual_salary(
        lcase.wage_rate_of_pay_from,
        lcase.wage_unit_of_pay
    )::numeric(12,2) AS annual_salary
FROM public.lca_cases lcase
JOIN google_feins gf ON gf.fein = lcase.employer_fein
JOIN public.companies c ON c.fein = lcase.employer_fein
JOIN jobpush.target_soc_roles target
  ON target.active
 AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
WHERE jobpush.lca_annual_salary(
        lcase.wage_rate_of_pay_from,
        lcase.wage_unit_of_pay
      ) IS NOT NULL
ORDER BY annual_salary ASC, decision_date DESC
LIMIT 15;

\echo '=== Count under 90k by job_title (last 3 years, top 20) ==='
WITH google_feins AS (
    SELECT unnest(member_feins) AS fein
    FROM jobpush.company_targets_consolidated
    WHERE consolidation_key IN ('google', 'alphabet-google')
    LIMIT 1
), enriched AS (
    SELECT
        lcase.job_title,
        target.representative_title AS soc_title,
        jobpush.lca_annual_salary(
            lcase.wage_rate_of_pay_from,
            lcase.wage_unit_of_pay
        ) AS annual_salary
    FROM public.lca_cases lcase
    JOIN google_feins gf ON gf.fein = lcase.employer_fein
    JOIN jobpush.target_soc_roles target
      ON target.active
     AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
    WHERE lcase.decision_date >= (
        SELECT MAX(decision_date) - INTERVAL '3 years'
        FROM public.lca_cases
    )
      AND jobpush.lca_annual_salary(
            lcase.wage_rate_of_pay_from,
            lcase.wage_unit_of_pay
          ) IS NOT NULL
)
SELECT
    job_title,
    soc_title,
    COUNT(*) AS filings_under_90k,
    MIN(annual_salary)::numeric(12,0) AS min_salary,
    MAX(annual_salary)::numeric(12,0) AS max_salary
FROM enriched
WHERE annual_salary < 90000
GROUP BY 1, 2
ORDER BY filings_under_90k DESC, min_salary ASC
LIMIT 20;
