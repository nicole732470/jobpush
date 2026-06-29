-- Operational crawl queue derived from the canonical analysis table.
-- Existing discovery/crawl state is preserved across scoring refreshes.
BEGIN;

INSERT INTO jobpush.crawl_targets (
    consolidation_key,
    canonical_name,
    priority_tier,
    computed_priority_tier,
    priority_source,
    priority_override_reason,
    priority_score,
    enabled,
    next_discovery_at,
    created_at,
    updated_at
)
SELECT
    target.consolidation_key,
    target.canonical_name,
    target.crawl_priority_tier,
    target.computed_crawl_priority_tier,
    CASE WHEN override.consolidation_key IS NULL
        THEN 'computed' ELSE 'manual_override' END,
    override.reason,
    target.priority_score,
    TRUE,
    now(),
    now(),
    now()
FROM jobpush.company_targets_consolidated target
LEFT JOIN jobpush.crawl_priority_overrides override
  ON override.consolidation_key = target.consolidation_key
 AND override.active
WHERE target.crawl_priority_tier IN ('P0', 'P1', 'P2', 'P3')
ON CONFLICT (consolidation_key) DO UPDATE SET
    canonical_name = EXCLUDED.canonical_name,
    priority_tier = EXCLUDED.priority_tier,
    computed_priority_tier = EXCLUDED.computed_priority_tier,
    priority_source = EXCLUDED.priority_source,
    priority_override_reason = EXCLUDED.priority_override_reason,
    priority_score = EXCLUDED.priority_score,
    enabled = TRUE,
    updated_at = now();

UPDATE jobpush.crawl_targets crawl
SET
    enabled = FALSE,
    updated_at = now()
WHERE crawl.enabled
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.company_targets_consolidated target
      WHERE target.consolidation_key = crawl.consolidation_key
        AND target.crawl_priority_tier IN ('P0', 'P1', 'P2', 'P3')
  );

UPDATE jobpush.crawl_targets crawl
SET
    computed_priority_tier = NULL,
    priority_source = 'computed',
    priority_override_reason = NULL,
    updated_at = now()
WHERE NOT crawl.enabled;

COMMIT;
