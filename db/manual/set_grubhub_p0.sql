-- Manual P0 for Grubhub Holdings Inc. (singleton FEIN key).
-- Prefer db/migrations/030_grubhub_priority_override.sql + run_migration_030.sh on RDS.
-- After INSERT, run refresh + sync (see run_migration_030.sh).

BEGIN;

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES (
    '26-1328194', 'P0', 'Manual highest-priority Grubhub Holdings Inc. selection', 'nicole', TRUE
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();

COMMIT;
