BEGIN;

ALTER TABLE jobpush.career_sites
    ADD COLUMN IF NOT EXISTS scope_method TEXT NOT NULL DEFAULT 'unknown';

ALTER TABLE jobpush.career_sites
    DROP CONSTRAINT IF EXISTS career_sites_scope_method_check;

ALTER TABLE jobpush.career_sites
    ADD CONSTRAINT career_sites_scope_method_check CHECK (scope_method IN (
        'server_filter', 'local_filter', 'verified_us_only', 'unknown'
    ));

ALTER TABLE jobpush.crawl_runs
    ADD COLUMN IF NOT EXISTS scope_method TEXT NOT NULL DEFAULT 'unknown';

ALTER TABLE jobpush.crawl_runs
    DROP CONSTRAINT IF EXISTS crawl_runs_scope_method_check;

ALTER TABLE jobpush.crawl_runs
    ADD CONSTRAINT crawl_runs_scope_method_check CHECK (scope_method IN (
        'server_filter', 'local_filter', 'verified_us_only', 'unknown'
    ));

UPDATE jobpush.career_sites SET scope_method = 'server_filter', updated_at = now()
WHERE site_id IN (38, 78, 287, 292);

UPDATE jobpush.career_sites SET scope_method = 'local_filter', updated_at = now()
WHERE site_id = 111;

UPDATE jobpush.career_sites SET scope_method = 'verified_us_only', updated_at = now()
WHERE site_id IN (70, 288);

CREATE OR REPLACE VIEW jobpush.crawl_scope_readiness AS
SELECT
    target.priority_tier,
    target.consolidation_key,
    target.canonical_name,
    site.site_id,
    site.source_type,
    site.site_url,
    site.target_country_code,
    site.scope_method,
    (site.target_country_code = 'US' AND site.scope_method <> 'unknown') AS us_scope_ready,
    site.crawl_status,
    site.last_success_at
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.verification_status = 'verified' AND site.crawl_enabled;

COMMIT;
