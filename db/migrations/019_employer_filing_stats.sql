BEGIN;

CREATE OR REPLACE FUNCTION jobpush.lca_annual_salary(
    wage_rate_of_pay_from NUMERIC,
    wage_unit_of_pay TEXT
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN wage_rate_of_pay_from IS NULL THEN NULL
        WHEN wage_unit_of_pay = 'Year' THEN wage_rate_of_pay_from
        WHEN wage_unit_of_pay = 'Month' THEN wage_rate_of_pay_from * 12
        WHEN wage_unit_of_pay = 'Bi-Weekly' THEN wage_rate_of_pay_from * 26
        WHEN wage_unit_of_pay = 'Week' THEN wage_rate_of_pay_from * 52
        WHEN wage_unit_of_pay = 'Hour' THEN wage_rate_of_pay_from * 2080
        ELSE NULL
    END;
$$;

CREATE TABLE IF NOT EXISTS jobpush.employer_filing_stats (
    fein                                TEXT PRIMARY KEY
                                        REFERENCES public.companies(fein) ON DELETE CASCADE,
    target_role_lca_count               INTEGER NOT NULL DEFAULT 0,
    target_role_min_annual_salary       NUMERIC(14, 2),
    target_role_valid_salary_lca_count  INTEGER NOT NULL DEFAULT 0,
    target_role_invalid_salary_lca_count INTEGER NOT NULL DEFAULT 0,
    has_product_role_job                BOOLEAN NOT NULL DEFAULT FALSE,
    has_product_manager_job             BOOLEAN NOT NULL DEFAULT FALSE,
    product_role_lca_count              INTEGER NOT NULL DEFAULT 0,
    last_decision_date                  DATE,
    dataset_max_decision_date           DATE,
    refreshed_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (target_role_lca_count >= 0),
    CHECK (target_role_valid_salary_lca_count >= 0),
    CHECK (target_role_invalid_salary_lca_count >= 0),
    CHECK (product_role_lca_count >= 0),
    CHECK (
        target_role_min_annual_salary IS NULL
        OR target_role_min_annual_salary >= 0
    )
);

CREATE INDEX IF NOT EXISTS idx_employer_filing_stats_last_decision
    ON jobpush.employer_filing_stats(last_decision_date DESC NULLS LAST);

COMMIT;
