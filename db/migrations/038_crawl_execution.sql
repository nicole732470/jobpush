BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.crawl_batches (
    batch_id BIGSERIAL PRIMARY KEY,
    batch_name TEXT NOT NULL UNIQUE,
    cohort TEXT NOT NULL,
    priority_tier TEXT,
    selection_rule TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'planned',
    planned_target_count INTEGER NOT NULL DEFAULT 0,
    attempted_target_count INTEGER NOT NULL DEFAULT 0,
    successful_target_count INTEGER NOT NULL DEFAULT 0,
    failed_target_count INTEGER NOT NULL DEFAULT 0,
    requests_count INTEGER NOT NULL DEFAULT 0,
    discovered_job_count INTEGER NOT NULL DEFAULT 0,
    target_job_count INTEGER NOT NULL DEFAULT 0,
    review_job_count INTEGER NOT NULL DEFAULT 0,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT crawl_batches_status_check
        CHECK (status IN ('planned', 'running', 'succeeded', 'partial', 'failed')),
    CONSTRAINT crawl_batches_tier_check
        CHECK (priority_tier IS NULL OR priority_tier IN ('P0', 'P1', 'P2'))
);

CREATE TABLE IF NOT EXISTS jobpush.crawl_batch_targets (
    batch_id BIGINT NOT NULL REFERENCES jobpush.crawl_batches(batch_id) ON DELETE CASCADE,
    consolidation_key TEXT NOT NULL REFERENCES jobpush.crawl_targets(consolidation_key),
    site_id BIGINT NOT NULL REFERENCES jobpush.career_sites(site_id),
    status TEXT NOT NULL DEFAULT 'planned',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (batch_id, site_id),
    CONSTRAINT crawl_batch_targets_status_check
        CHECK (status IN ('planned', 'running', 'succeeded', 'failed', 'skipped'))
);

CREATE TABLE IF NOT EXISTS jobpush.crawl_runs (
    run_id BIGSERIAL PRIMARY KEY,
    batch_id BIGINT REFERENCES jobpush.crawl_batches(batch_id) ON DELETE SET NULL,
    site_id BIGINT NOT NULL REFERENCES jobpush.career_sites(site_id),
    adapter_name TEXT NOT NULL,
    adapter_version TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'running',
    requests_count INTEGER NOT NULL DEFAULT 0,
    pages_fetched INTEGER NOT NULL DEFAULT 0,
    last_http_status INTEGER,
    latency_ms INTEGER,
    raw_job_count INTEGER NOT NULL DEFAULT 0,
    parsed_job_count INTEGER NOT NULL DEFAULT 0,
    duplicate_count INTEGER NOT NULL DEFAULT 0,
    new_job_count INTEGER NOT NULL DEFAULT 0,
    updated_job_count INTEGER NOT NULL DEFAULT 0,
    closed_job_count INTEGER NOT NULL DEFAULT 0,
    target_job_count INTEGER NOT NULL DEFAULT 0,
    review_job_count INTEGER NOT NULL DEFAULT 0,
    error_code TEXT,
    error_message TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    CONSTRAINT crawl_runs_status_check
        CHECK (status IN ('running', 'succeeded', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_crawl_runs_site_started
    ON jobpush.crawl_runs(site_id, started_at DESC);

CREATE TABLE IF NOT EXISTS jobpush.job_title_labels (
    normalized_title TEXT PRIMARY KEY,
    classification_status TEXT NOT NULL DEFAULT 'review',
    canonical_role TEXT,
    rule_version TEXT,
    decision_reason TEXT,
    labeled_by TEXT,
    labeled_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT job_title_labels_status_check
        CHECK (classification_status IN ('review', 'target', 'non_target'))
);

CREATE TABLE IF NOT EXISTS jobpush.job_postings (
    site_id BIGINT NOT NULL REFERENCES jobpush.career_sites(site_id),
    external_job_id TEXT NOT NULL,
    consolidation_key TEXT NOT NULL REFERENCES jobpush.crawl_targets(consolidation_key),
    title TEXT NOT NULL,
    normalized_title TEXT NOT NULL,
    location TEXT,
    category TEXT,
    job_url TEXT NOT NULL,
    description_snippet TEXT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at TIMESTAMPTZ,
    last_run_id BIGINT REFERENCES jobpush.crawl_runs(run_id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, external_job_id)
);

CREATE INDEX IF NOT EXISTS idx_job_postings_company_active
    ON jobpush.job_postings(consolidation_key, active, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS idx_job_postings_title
    ON jobpush.job_postings(normalized_title);

CREATE OR REPLACE VIEW jobpush.job_title_catalog AS
SELECT
    posting.normalized_title,
    min(posting.title) AS example_title,
    count(*) AS posting_count,
    count(DISTINCT posting.consolidation_key) AS company_count,
    count(*) FILTER (WHERE posting.active) AS active_posting_count,
    COALESCE(label.classification_status, 'review') AS classification_status,
    label.canonical_role,
    label.rule_version,
    label.decision_reason,
    label.labeled_by,
    label.labeled_at
FROM jobpush.job_postings posting
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
GROUP BY posting.normalized_title, label.classification_status, label.canonical_role,
         label.rule_version, label.decision_reason, label.labeled_by, label.labeled_at;

COMMIT;
