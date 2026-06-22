BEGIN;

-- Optional cleanup after FY2025 Q1 wage repair scores are verified stable.
-- JobPush-only tables; does not modify public.lca_cases or JobLens objects.

DROP TABLE IF EXISTS jobpush.lca_wage_repair_stage;
DROP TABLE IF EXISTS jobpush.lca_wage_repair_backup;

COMMIT;
