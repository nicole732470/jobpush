-- Keep Jobs to Apply fast: company search resolves to consolidation_key, then
-- reads active US jobs by company/date. These indexes support that path.
CREATE INDEX IF NOT EXISTS idx_job_postings_us_company_first_seen
    ON jobpush.job_postings(consolidation_key, first_seen_at DESC)
    WHERE active AND market_scope = 'US';

CREATE INDEX IF NOT EXISTS idx_job_postings_us_first_seen
    ON jobpush.job_postings(first_seen_at DESC)
    WHERE active AND market_scope = 'US';

CREATE INDEX IF NOT EXISTS idx_crawl_targets_canonical_name
    ON jobpush.crawl_targets(canonical_name);
