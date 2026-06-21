BEGIN;

WITH filing_stats AS (
    SELECT
        employer_fein AS fein,
        COUNT(*) FILTER (
            WHERE LEFT(REGEXP_REPLACE(COALESCE(soc_code, ''), '[^0-9]', '', 'g'), 2)
                  IN ('11', '13', '15')
        )::INTEGER AS target_role_lca_count,
        MAX(decision_date) AS last_decision_date
    FROM public.lca_cases
    WHERE employer_fein IS NOT NULL
    GROUP BY employer_fein
), source AS (
    SELECT
        c.fein,
        c.company_id,
        c.name AS company_name,
        c.naics_code,
        c.naics_sector,
        c.city AS employer_city,
        c.state AS employer_state,
        c.lca_count,
        c.certified_count,
        (c.lca_count = 1) AS single_lca_company,
        COALESCE(f.target_role_lca_count, 0) > 0 AS target_role_match,
        COALESCE(f.target_role_lca_count, 0) AS target_role_lca_count,
        f.last_decision_date,
        CASE WHEN COALESCE(f.target_role_lca_count, 0) > 0 THEN 1 ELSE 0 END
            AS priority_score
    FROM public.companies c
    LEFT JOIN filing_stats f USING (fein)
)
INSERT INTO jobpush.company_targets (
    fein, company_id, company_name, naics_code, naics_sector,
    employer_city, employer_state, lca_count, certified_count,
    single_lca_company, target_role_match, target_role_lca_count,
    last_decision_date, priority_score, priority_version, updated_at
)
SELECT
    fein, company_id, company_name, naics_code, naics_sector,
    employer_city, employer_state, lca_count, certified_count,
    single_lca_company, target_role_match, target_role_lca_count,
    last_decision_date, priority_score, 'v1', now()
FROM source
ON CONFLICT (fein) DO UPDATE SET
    company_id = EXCLUDED.company_id,
    company_name = EXCLUDED.company_name,
    naics_code = EXCLUDED.naics_code,
    naics_sector = EXCLUDED.naics_sector,
    employer_city = EXCLUDED.employer_city,
    employer_state = EXCLUDED.employer_state,
    lca_count = EXCLUDED.lca_count,
    certified_count = EXCLUDED.certified_count,
    single_lca_company = EXCLUDED.single_lca_company,
    target_role_match = EXCLUDED.target_role_match,
    target_role_lca_count = EXCLUDED.target_role_lca_count,
    last_decision_date = EXCLUDED.last_decision_date,
    priority_score = EXCLUDED.priority_score,
    priority_version = EXCLUDED.priority_version,
    updated_at = now();

DELETE FROM jobpush.company_targets t
WHERE NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.fein = t.fein);

COMMIT;

