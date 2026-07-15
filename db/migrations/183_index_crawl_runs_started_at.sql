CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_crawl_runs_started_at
    ON jobpush.crawl_runs(started_at DESC);
