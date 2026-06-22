BEGIN;

WITH dataset_window AS (
    SELECT MAX(decision_date) AS max_decision_date
    FROM public.lca_cases
), filing_stats AS (
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
), source_base AS (
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
        COALESCE(f.last_decision_date >= w.max_decision_date - 365, FALSE)
            AS recent_lca
    FROM public.companies c
    LEFT JOIN filing_stats f USING (fein)
    CROSS JOIN dataset_window w
), source AS (
    SELECT
        source_base.*,
        CASE WHEN target_role_match THEN 1 ELSE 0 END
        + CASE WHEN recent_lca THEN 1 ELSE 0 END
        + CASE WHEN certified_count > 0 THEN 1 ELSE 0 END
        + CASE
            WHEN lca_count >= 100 THEN 3
            WHEN lca_count >= 25 THEN 2
            WHEN lca_count >= 5 THEN 1
            ELSE 0
          END AS priority_score
    FROM source_base
)
INSERT INTO jobpush.company_targets (
    fein, company_id, company_name, naics_code, naics_sector,
    employer_city, employer_state, lca_count, certified_count,
    single_lca_company, target_role_match, target_role_lca_count,
    last_decision_date, recent_lca, priority_score, priority_version, updated_at
)
SELECT
    fein, company_id, company_name, naics_code, naics_sector,
    employer_city, employer_state, lca_count, certified_count,
    single_lca_company, target_role_match, target_role_lca_count,
    last_decision_date, recent_lca, priority_score, 'v2', now()
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
    recent_lca = EXCLUDED.recent_lca,
    priority_score = EXCLUDED.priority_score,
    priority_version = EXCLUDED.priority_version,
    updated_at = now();

DELETE FROM jobpush.company_targets t
WHERE NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.fein = t.fein);

COMMIT;
