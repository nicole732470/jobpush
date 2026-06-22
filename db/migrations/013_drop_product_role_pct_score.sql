BEGIN;

ALTER TABLE jobpush.company_targets
    DROP CONSTRAINT IF EXISTS company_targets_product_role_pct_score_check;

ALTER TABLE jobpush.company_targets
    DROP COLUMN IF EXISTS product_role_pct_score;

COMMIT;
