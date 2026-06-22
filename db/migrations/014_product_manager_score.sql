BEGIN;

CREATE OR REPLACE FUNCTION jobpush.is_product_manager_job_title(title TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT jobpush.product_role_job_title_category(title) = 'product_manager';
$$;

ALTER TABLE jobpush.company_targets
    ADD COLUMN IF NOT EXISTS product_manager_score NUMERIC(4, 2) NOT NULL DEFAULT 0;

ALTER TABLE jobpush.company_targets
    DROP CONSTRAINT IF EXISTS company_targets_product_manager_score_check;

ALTER TABLE jobpush.company_targets
    ADD CONSTRAINT company_targets_product_manager_score_check
    CHECK (product_manager_score >= 0);

ALTER TABLE jobpush.company_targets
    ALTER COLUMN product_manager_score TYPE NUMERIC(4, 2)
    USING product_manager_score::NUMERIC(4, 2);

ALTER TABLE jobpush.company_targets
    ALTER COLUMN priority_score TYPE NUMERIC(4, 2)
    USING priority_score::NUMERIC(4, 2);

COMMIT;
