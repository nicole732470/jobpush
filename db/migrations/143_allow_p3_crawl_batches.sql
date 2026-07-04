ALTER TABLE jobpush.crawl_batches
    DROP CONSTRAINT IF EXISTS crawl_batches_tier_check;

ALTER TABLE jobpush.crawl_batches
    ADD CONSTRAINT crawl_batches_tier_check
    CHECK (priority_tier IN ('P0', 'P1', 'P2', 'P3'));
