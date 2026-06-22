BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.crawl_priority_overrides (
    consolidation_key TEXT PRIMARY KEY,
    override_tier TEXT NOT NULL,
    reason TEXT NOT NULL,
    created_by TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT crawl_priority_overrides_tier_check
        CHECK (override_tier IN ('P0', 'P1', 'P2'))
);

ALTER TABLE jobpush.company_targets_consolidated
    ADD COLUMN IF NOT EXISTS computed_crawl_priority_tier TEXT;

ALTER TABLE jobpush.company_targets_consolidated
    DROP CONSTRAINT IF EXISTS company_targets_consolidated_computed_tier_check;

ALTER TABLE jobpush.company_targets_consolidated
    ADD CONSTRAINT company_targets_consolidated_computed_tier_check
    CHECK (
        computed_crawl_priority_tier IS NULL
        OR computed_crawl_priority_tier IN ('P1', 'P2')
    );

ALTER TABLE jobpush.crawl_targets
    ADD COLUMN IF NOT EXISTS computed_priority_tier TEXT,
    ADD COLUMN IF NOT EXISTS priority_source TEXT NOT NULL DEFAULT 'computed',
    ADD COLUMN IF NOT EXISTS priority_override_reason TEXT;

ALTER TABLE jobpush.crawl_targets
    DROP CONSTRAINT IF EXISTS crawl_targets_computed_priority_tier_check,
    DROP CONSTRAINT IF EXISTS crawl_targets_priority_source_check;

ALTER TABLE jobpush.crawl_targets
    ADD CONSTRAINT crawl_targets_computed_priority_tier_check
        CHECK (computed_priority_tier IS NULL OR computed_priority_tier IN ('P1', 'P2')),
    ADD CONSTRAINT crawl_targets_priority_source_check
        CHECK (priority_source IN ('computed', 'manual_override'));

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES
    ('salesforce', 'P0', 'Manual highest-priority company selection', 'nicole', TRUE),
    ('13-3924155', 'P0', 'Manual highest-priority Cognizant US entity', 'nicole', TRUE),
    ('13-3386776', 'P2', 'Manual downgrade outside computed tier rule', 'nicole', TRUE)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();

COMMIT;
