BEGIN;

ALTER TABLE jobpush.company_targets_consolidated
    ADD COLUMN IF NOT EXISTS target_role_min_annual_salary NUMERIC(14, 2),
    ADD COLUMN IF NOT EXISTS target_role_valid_salary_lca_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS target_role_invalid_salary_lca_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS salary_score NUMERIC(3, 1) NOT NULL DEFAULT 0;

ALTER TABLE jobpush.company_targets_consolidated
    DROP CONSTRAINT IF EXISTS company_targets_consolidated_salary_score_check,
    DROP CONSTRAINT IF EXISTS company_targets_consolidated_salary_counts_check,
    DROP CONSTRAINT IF EXISTS company_targets_consolidated_min_salary_check;

ALTER TABLE jobpush.company_targets_consolidated
    ADD CONSTRAINT company_targets_consolidated_salary_score_check
        CHECK (salary_score IN (0, 1)),
    ADD CONSTRAINT company_targets_consolidated_salary_counts_check
        CHECK (
            target_role_valid_salary_lca_count >= 0
            AND target_role_invalid_salary_lca_count >= 0
        ),
    ADD CONSTRAINT company_targets_consolidated_min_salary_check
        CHECK (
            target_role_min_annual_salary IS NULL
            OR target_role_min_annual_salary >= 0
        );

COMMIT;
