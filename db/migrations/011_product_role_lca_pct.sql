BEGIN;

ALTER TABLE jobpush.company_targets
    ADD COLUMN IF NOT EXISTS product_role_lca_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE jobpush.company_targets
    ADD COLUMN IF NOT EXISTS product_role_lca_pct NUMERIC(5, 2) NOT NULL DEFAULT 0;

ALTER TABLE jobpush.company_targets
    DROP CONSTRAINT IF EXISTS company_targets_product_role_lca_count_check;

ALTER TABLE jobpush.company_targets
    ADD CONSTRAINT company_targets_product_role_lca_count_check
    CHECK (product_role_lca_count >= 0);

ALTER TABLE jobpush.company_targets
    DROP CONSTRAINT IF EXISTS company_targets_product_role_lca_pct_check;

ALTER TABLE jobpush.company_targets
    ADD CONSTRAINT company_targets_product_role_lca_pct_check
    CHECK (product_role_lca_pct >= 0 AND product_role_lca_pct <= 100);

COMMIT;
