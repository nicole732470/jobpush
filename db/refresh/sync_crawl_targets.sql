-- Operational crawl queue derived from the canonical analysis table.
-- Existing discovery/crawl state is preserved across scoring refreshes.
BEGIN;

INSERT INTO jobpush.crawl_targets (
    consolidation_key,
    canonical_name,
    priority_tier,
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
    target.priority_score,
    TRUE,
    now(),
    now(),
    now()
FROM jobpush.company_targets_consolidated target
WHERE target.crawl_priority_tier IN ('P0', 'P1', 'P2')
ON CONFLICT (consolidation_key) DO UPDATE SET
    canonical_name = EXCLUDED.canonical_name,
    priority_tier = EXCLUDED.priority_tier,
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
        AND target.crawl_priority_tier IN ('P0', 'P1', 'P2')
  );

COMMIT;
