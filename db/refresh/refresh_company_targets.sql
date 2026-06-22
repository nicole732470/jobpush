BEGIN;

WITH dataset_window AS (
    SELECT MAX(decision_date) AS max_decision_date
    FROM public.lca_cases
), filing_stats AS (
    SELECT
        l.employer_fein AS fein,
        COUNT(target.normalized_soc_code)::INTEGER AS target_role_lca_count,
        MAX(l.decision_date) AS last_decision_date
    FROM public.lca_cases l
    LEFT JOIN jobpush.target_soc_roles target
        ON target.active
       AND target.normalized_soc_code = jobpush.normalize_soc_code(l.soc_code)
    WHERE l.employer_fein IS NOT NULL
    GROUP BY l.employer_fein
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
        COALESCE(f.target_role_lca_count, 0) AS target_role_lca_count,
        f.last_decision_date,
        COALESCE(f.last_decision_date >= w.max_decision_date - 365, FALSE)
            AS recent_lca
    FROM public.companies c
    LEFT JOIN filing_stats f USING (fein)
    CROSS JOIN dataset_window w
), scored AS (
    SELECT
        source_base.*,
        CASE WHEN target_role_lca_count > 0 THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS target_role_score,
        CASE WHEN target_role_lca_count > 0 AND lca_count > 5 THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS lca_count_score,
        CASE WHEN target_role_lca_count > 0
              AND jobpush.is_chicago_metro(employer_city, employer_state)
            THEN 0.5::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS chicago_score
    FROM source_base
), totaled AS (
    SELECT
        scored.*,
        (target_role_score + lca_count_score + chicago_score)::NUMERIC(4, 1)
            AS priority_score
    FROM scored
)
INSERT INTO jobpush.company_targets (
    fein, company_id, company_name, naics_code, naics_sector,
    employer_city, employer_state, lca_count, certified_count,
    single_lca_company, target_role_lca_count,
    last_decision_date, recent_lca, target_role_score, lca_count_score,
    chicago_score, priority_score, priority_version, updated_at
)
SELECT
    fein, company_id, company_name, naics_code, naics_sector,
    employer_city, employer_state, lca_count, certified_count,
    single_lca_company, target_role_lca_count,
    last_decision_date, recent_lca, target_role_score, lca_count_score,
    chicago_score, priority_score, 'priority-v3', now()
FROM totaled
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
    target_role_lca_count = EXCLUDED.target_role_lca_count,
    last_decision_date = EXCLUDED.last_decision_date,
    recent_lca = EXCLUDED.recent_lca,
    target_role_score = EXCLUDED.target_role_score,
    lca_count_score = EXCLUDED.lca_count_score,
    chicago_score = EXCLUDED.chicago_score,
    priority_score = EXCLUDED.priority_score,
    priority_version = EXCLUDED.priority_version,
    updated_at = now();

DELETE FROM jobpush.company_targets t
WHERE NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.fein = t.fein);

COMMIT;
