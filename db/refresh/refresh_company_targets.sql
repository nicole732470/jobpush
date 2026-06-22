-- Per-FEIN audit table. Reads jobpush.employer_filing_stats (not public.lca_cases).

BEGIN;

WITH dataset_window AS (
    SELECT COALESCE(MAX(dataset_max_decision_date), MAX(last_decision_date)) AS max_decision_date
    FROM jobpush.employer_filing_stats
), source_base AS (
    SELECT
        company_row.fein,
        company_row.company_id,
        company_row.name AS company_name,
        company_row.naics_code,
        company_row.naics_sector,
        company_row.city AS employer_city,
        company_row.state AS employer_state,
        company_row.lca_count,
        company_row.certified_count,
        (company_row.lca_count = 1) AS single_lca_company,
        COALESCE(stats.target_role_lca_count, 0) AS target_role_lca_count,
        COALESCE(stats.has_product_role_job, FALSE) AS has_product_role_job,
        COALESCE(stats.has_product_manager_job, FALSE) AS has_product_manager_job,
        COALESCE(stats.product_role_lca_count, 0) AS product_role_lca_count,
        ROUND(
            100.0 * COALESCE(stats.product_role_lca_count, 0)
                / NULLIF(company_row.lca_count, 0),
            2
        ) AS product_role_lca_pct,
        stats.last_decision_date,
        COALESCE(
            stats.last_decision_date >= window_row.max_decision_date - 365,
            FALSE
        ) AS recent_lca
    FROM public.companies company_row
    LEFT JOIN jobpush.employer_filing_stats stats
      ON stats.fein = company_row.fein
    CROSS JOIN dataset_window window_row
), scored AS (
    SELECT
        source_base.*,
        CASE WHEN target_role_lca_count > 0 THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS target_role_score,
        CASE WHEN target_role_lca_count > 0 AND lca_count > 1 THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS lca_count_score,
        CASE WHEN target_role_lca_count > 0
              AND jobpush.is_chicago_metro(employer_city, employer_state)
            THEN 0.5::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS chicago_score,
        CASE WHEN target_role_lca_count > 0 AND has_product_role_job
            THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
            AS product_role_score,
        CASE WHEN target_role_lca_count > 0 AND has_product_manager_job
            THEN 0.25::NUMERIC(4, 2) ELSE 0::NUMERIC(4, 2) END
            AS product_manager_score,
        CASE WHEN EXISTS (
            SELECT 1
            FROM jobpush.linkedin_top_employer_company_matches match_row
            WHERE match_row.fein = source_base.fein
        ) THEN 1::NUMERIC(3, 1) ELSE 0::NUMERIC(3, 1) END
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
INSERT INTO jobpush.company_targets (
    fein, company_id, company_name, naics_code, naics_sector,
    employer_city, employer_state, lca_count, certified_count,
    single_lca_company, target_role_lca_count,
    last_decision_date, recent_lca, target_role_score, lca_count_score,
    chicago_score, product_role_score, product_manager_score,
    linkedin_top_employer_score, product_role_lca_count, product_role_lca_pct,
    priority_score, priority_version, updated_at
)
SELECT
    fein, company_id, company_name, naics_code, naics_sector,
    employer_city, employer_state, lca_count, certified_count,
    single_lca_company, target_role_lca_count,
    last_decision_date, recent_lca, target_role_score, lca_count_score,
    chicago_score, product_role_score, product_manager_score,
    linkedin_top_employer_score, product_role_lca_count, product_role_lca_pct,
    priority_score, 'priority-v7', now()
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
    product_role_score = EXCLUDED.product_role_score,
    product_manager_score = EXCLUDED.product_manager_score,
    linkedin_top_employer_score = EXCLUDED.linkedin_top_employer_score,
    product_role_lca_count = EXCLUDED.product_role_lca_count,
    product_role_lca_pct = EXCLUDED.product_role_lca_pct,
    priority_score = EXCLUDED.priority_score,
    priority_version = EXCLUDED.priority_version,
    updated_at = now();

DELETE FROM jobpush.company_targets target_row
WHERE NOT EXISTS (
    SELECT 1 FROM public.companies company_row WHERE company_row.fein = target_row.fein
);

COMMIT;
