BEGIN;

ALTER TABLE jobpush.crawl_targets
    DROP CONSTRAINT IF EXISTS crawl_targets_discovery_status_check;

ALTER TABLE jobpush.crawl_targets
    ADD CONSTRAINT crawl_targets_discovery_status_check
    CHECK (discovery_status IN (
        'pending', 'running', 'review_pending', 'found', 'not_found',
        'retry', 'blocked', 'paused'
    ));

ALTER TABLE jobpush.career_sites
    ADD COLUMN IF NOT EXISTS candidate_rank INTEGER,
    ADD COLUMN IF NOT EXISTS candidate_score NUMERIC(7, 3),
    ADD COLUMN IF NOT EXISTS search_query TEXT,
    ADD COLUMN IF NOT EXISTS evidence_title TEXT,
    ADD COLUMN IF NOT EXISTS evidence_snippet TEXT,
    ADD COLUMN IF NOT EXISTS last_discovered_at TIMESTAMPTZ;

ALTER TABLE jobpush.career_sites
    DROP CONSTRAINT IF EXISTS career_sites_candidate_rank_check,
    DROP CONSTRAINT IF EXISTS career_sites_candidate_score_check;

ALTER TABLE jobpush.career_sites
    ADD CONSTRAINT career_sites_candidate_rank_check
        CHECK (candidate_rank IS NULL OR candidate_rank > 0),
    ADD CONSTRAINT career_sites_candidate_score_check
        CHECK (candidate_score IS NULL OR candidate_score >= 0);

CREATE TABLE IF NOT EXISTS jobpush.career_site_discovery_runs (
    run_id TEXT PRIMARY KEY,
    cohort TEXT NOT NULL,
    target_count INTEGER NOT NULL DEFAULT 0,
    search_count INTEGER NOT NULL DEFAULT 0,
    candidate_count INTEGER NOT NULL DEFAULT 0,
    error_count INTEGER NOT NULL DEFAULT 0,
    estimated_credits INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'running',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    notes TEXT,
    CONSTRAINT career_site_discovery_runs_counts_check CHECK (
        target_count >= 0 AND search_count >= 0 AND candidate_count >= 0
        AND error_count >= 0 AND estimated_credits >= 0
    ),
    CONSTRAINT career_site_discovery_runs_status_check
        CHECK (status IN ('running', 'completed', 'failed'))
);

CREATE TABLE IF NOT EXISTS jobpush.career_site_discovery_stage (
    run_id TEXT NOT NULL,
    consolidation_key TEXT NOT NULL,
    canonical_name TEXT NOT NULL,
    search_query TEXT NOT NULL,
    candidate_rank INTEGER NOT NULL,
    candidate_score NUMERIC(7, 3) NOT NULL,
    site_url TEXT NOT NULL,
    normalized_domain TEXT,
    site_kind TEXT NOT NULL,
    source_type TEXT NOT NULL,
    source_key TEXT,
    evidence_title TEXT,
    evidence_snippet TEXT,
    PRIMARY KEY (run_id, consolidation_key, site_url)
);

CREATE TABLE IF NOT EXISTS jobpush.career_site_discovery_result_stage (
    run_id TEXT NOT NULL,
    consolidation_key TEXT NOT NULL,
    canonical_name TEXT NOT NULL,
    search_query TEXT NOT NULL,
    search_succeeded BOOLEAN NOT NULL,
    candidate_count INTEGER NOT NULL,
    error_message TEXT,
    PRIMARY KEY (run_id, consolidation_key)
);

COMMIT;
