BEGIN;

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES (
    '36-2756407',
    'P0',
    'Manual highest-priority The Options Clearing Corporation selection',
    'nicole',
    TRUE
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();

COMMIT;
