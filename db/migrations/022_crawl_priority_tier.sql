BEGIN;

ALTER TABLE jobpush.company_targets_consolidated
    ADD COLUMN IF NOT EXISTS crawl_priority_tier TEXT;

ALTER TABLE jobpush.company_targets_consolidated
    DROP CONSTRAINT IF EXISTS company_targets_consolidated_crawl_priority_tier_check;

ALTER TABLE jobpush.company_targets_consolidated
    ADD CONSTRAINT company_targets_consolidated_crawl_priority_tier_check
    CHECK (crawl_priority_tier IS NULL OR crawl_priority_tier IN ('P0', 'P1', 'P2'));

CREATE INDEX IF NOT EXISTS idx_company_targets_consolidated_crawl_tier
    ON jobpush.company_targets_consolidated(crawl_priority_tier, priority_score DESC)
    WHERE crawl_priority_tier IS NOT NULL;

COMMIT;
