-- Manual P0 for Google / Alphabet merged groups.
-- Stored in crawl_priority_overrides (migration 027). Do NOT UPDATE crawl_priority_tier directly.
-- Prefer db/run_migration_027.sh on RDS.

BEGIN;

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES
    ('google', 'P0', 'Manual highest-priority Google selection', 'nicole', TRUE),
    ('alphabet-google', 'P0', 'Manual highest-priority Alphabet/Google selection', 'nicole', TRUE)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();

COMMIT;
