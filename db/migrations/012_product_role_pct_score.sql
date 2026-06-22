BEGIN;

ALTER TABLE jobpush.company_targets
    ADD COLUMN IF NOT EXISTS product_role_pct_score NUMERIC(3, 1) NOT NULL DEFAULT 0;

ALTER TABLE jobpush.company_targets
    DROP CONSTRAINT IF EXISTS company_targets_product_role_pct_score_check;

ALTER TABLE jobpush.company_targets
    ADD CONSTRAINT company_targets_product_role_pct_score_check
    CHECK (product_role_pct_score >= 0);

COMMIT;
