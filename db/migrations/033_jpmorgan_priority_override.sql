BEGIN;

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES (
    '13-2624428', 'P0', 'Manual highest-priority JPMorgan Chase & Co. selection', 'nicole', TRUE
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();

COMMIT;
