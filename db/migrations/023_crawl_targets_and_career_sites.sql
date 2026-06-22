BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.crawl_targets (
    consolidation_key TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    priority_tier TEXT NOT NULL,
    priority_score NUMERIC(4, 2) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    discovery_status TEXT NOT NULL DEFAULT 'pending',
    next_discovery_at TIMESTAMPTZ DEFAULT now(),
    last_discovery_at TIMESTAMPTZ,
    last_discovery_success_at TIMESTAMPTZ,
    consecutive_discovery_failures INTEGER NOT NULL DEFAULT 0,
    last_discovery_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT crawl_targets_priority_tier_check
        CHECK (priority_tier IN ('P0', 'P1', 'P2')),
    CONSTRAINT crawl_targets_priority_score_check
        CHECK (priority_score >= 0),
    CONSTRAINT crawl_targets_discovery_status_check
        CHECK (discovery_status IN (
            'pending', 'running', 'found', 'not_found', 'retry', 'blocked', 'paused'
        )),
    CONSTRAINT crawl_targets_discovery_failures_check
        CHECK (consecutive_discovery_failures >= 0)
);

CREATE INDEX IF NOT EXISTS idx_crawl_targets_due_discovery
    ON jobpush.crawl_targets(priority_tier, next_discovery_at, priority_score DESC)
    WHERE enabled AND discovery_status IN ('pending', 'not_found', 'retry');

CREATE INDEX IF NOT EXISTS idx_crawl_targets_tier
    ON jobpush.crawl_targets(priority_tier, priority_score DESC)
    WHERE enabled;

CREATE TABLE IF NOT EXISTS jobpush.career_sites (
    site_id BIGSERIAL PRIMARY KEY,
    consolidation_key TEXT NOT NULL,
    site_url TEXT NOT NULL,
    normalized_domain TEXT,
    site_kind TEXT NOT NULL DEFAULT 'careers',
    source_type TEXT NOT NULL DEFAULT 'unknown',
    source_key TEXT,
    discovery_source TEXT,
    verification_status TEXT NOT NULL DEFAULT 'unverified',
    crawl_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    crawl_status TEXT NOT NULL DEFAULT 'pending',
    crawl_interval_hours INTEGER,
    next_crawl_at TIMESTAMPTZ,
    last_crawled_at TIMESTAMPTZ,
    last_success_at TIMESTAMPTZ,
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    response_etag TEXT,
    response_last_modified TEXT,
    content_hash TEXT,
    last_error TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT career_sites_crawl_target_fk
        FOREIGN KEY (consolidation_key)
        REFERENCES jobpush.crawl_targets(consolidation_key)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT career_sites_unique_company_url
        UNIQUE (consolidation_key, site_url),
    CONSTRAINT career_sites_site_kind_check
        CHECK (site_kind IN ('corporate', 'careers', 'ats_feed')),
    CONSTRAINT career_sites_verification_status_check
        CHECK (verification_status IN ('unverified', 'verified', 'rejected')),
    CONSTRAINT career_sites_crawl_status_check
        CHECK (crawl_status IN ('pending', 'running', 'succeeded', 'failed', 'paused')),
    CONSTRAINT career_sites_interval_check
        CHECK (crawl_interval_hours IS NULL OR crawl_interval_hours > 0),
    CONSTRAINT career_sites_failures_check
        CHECK (consecutive_failures >= 0)
);

CREATE INDEX IF NOT EXISTS idx_career_sites_due_crawl
    ON jobpush.career_sites(next_crawl_at, consolidation_key)
    WHERE crawl_enabled
      AND verification_status = 'verified'
      AND crawl_status IN ('pending', 'succeeded', 'failed');

CREATE INDEX IF NOT EXISTS idx_career_sites_company
    ON jobpush.career_sites(consolidation_key, verification_status);

COMMIT;
