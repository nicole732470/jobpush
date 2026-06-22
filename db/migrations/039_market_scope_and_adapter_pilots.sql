BEGIN;

ALTER TABLE jobpush.career_sites
    ADD COLUMN IF NOT EXISTS target_country_code TEXT;

ALTER TABLE jobpush.career_sites
    DROP CONSTRAINT IF EXISTS career_sites_target_country_check;

ALTER TABLE jobpush.career_sites
    ADD CONSTRAINT career_sites_target_country_check
        CHECK (target_country_code IS NULL OR target_country_code ~ '^[A-Z]{2}$');

ALTER TABLE jobpush.crawl_runs
    ADD COLUMN IF NOT EXISTS crawl_scope TEXT NOT NULL DEFAULT 'global';

ALTER TABLE jobpush.crawl_runs
    DROP CONSTRAINT IF EXISTS crawl_runs_scope_check;

ALTER TABLE jobpush.crawl_runs
    ADD CONSTRAINT crawl_runs_scope_check
        CHECK (crawl_scope IN ('global', 'US'));

ALTER TABLE jobpush.job_postings
    ADD COLUMN IF NOT EXISTS market_scope TEXT NOT NULL DEFAULT 'unknown',
    ADD COLUMN IF NOT EXISTS posted_text TEXT,
    ADD COLUMN IF NOT EXISTS employment_type TEXT;

ALTER TABLE jobpush.job_postings
    DROP CONSTRAINT IF EXISTS job_postings_market_scope_check;

ALTER TABLE jobpush.job_postings
    ADD CONSTRAINT job_postings_market_scope_check
        CHECK (market_scope IN ('US', 'non-US', 'unknown'));

UPDATE jobpush.job_postings
SET market_scope = CASE
    WHEN location LIKE 'US-%' THEN 'US'
    WHEN location IS NULL OR btrim(location) = '' THEN 'unknown'
    ELSE 'non-US'
END
WHERE consolidation_key = '77-0080465';

UPDATE jobpush.career_sites
SET target_country_code = 'US', updated_at = now()
WHERE site_id IN (70, 78, 288);

CREATE INDEX IF NOT EXISTS idx_job_postings_us_active
    ON jobpush.job_postings(consolidation_key, last_seen_at DESC)
    WHERE active AND market_scope = 'US';

CREATE OR REPLACE VIEW jobpush.job_postings_us AS
SELECT posting.*
FROM jobpush.job_postings posting
WHERE posting.active AND posting.market_scope = 'US';

COMMIT;
