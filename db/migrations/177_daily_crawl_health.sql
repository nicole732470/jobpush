BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.crawl_health_runs (
    health_run_id BIGSERIAL PRIMARY KEY,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'running',
    stale_runs_recovered INTEGER NOT NULL DEFAULT 0,
    transient_sites_requeued INTEGER NOT NULL DEFAULT 0,
    stale_urls_demoted INTEGER NOT NULL DEFAULT 0,
    chronic_sites_quarantined INTEGER NOT NULL DEFAULT 0,
    failed_sites_remaining INTEGER NOT NULL DEFAULT 0,
    failure_groups JSONB NOT NULL DEFAULT '[]'::jsonb,
    CONSTRAINT crawl_health_runs_status_check CHECK (status IN ('running','succeeded','failed'))
);

COMMIT;
