BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.job_description_snapshots (
    site_id BIGINT NOT NULL,
    external_job_id TEXT NOT NULL,
    source_fingerprint TEXT NOT NULL,
    raw_html TEXT,
    cleaned_description TEXT,
    content_type TEXT,
    apply_url TEXT,
    work_arrangement TEXT,
    salary_text TEXT,
    posted_date DATE,
    scrape_status TEXT NOT NULL DEFAULT 'pending',
    scrape_error TEXT,
    http_status INTEGER,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    scraped_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, external_job_id),
    FOREIGN KEY (site_id, external_job_id)
      REFERENCES jobpush.job_postings(site_id, external_job_id)
      ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT job_description_scrape_status_check
      CHECK (scrape_status IN ('pending','succeeded','failed','skipped'))
);

CREATE INDEX IF NOT EXISTS idx_job_description_snapshots_status
    ON jobpush.job_description_snapshots(scrape_status, updated_at);

CREATE TABLE IF NOT EXISTS jobpush.daily_job_exports (
    export_date DATE PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'running',
    export_path TEXT,
    jobs_discovered INTEGER NOT NULL DEFAULT 0,
    jobs_processed INTEGER NOT NULL DEFAULT 0,
    successful_jd_retrieval INTEGER NOT NULL DEFAULT 0,
    skipped_jobs INTEGER NOT NULL DEFAULT 0,
    failed_jobs INTEGER NOT NULL DEFAULT 0,
    exported_jobs INTEGER NOT NULL DEFAULT 0,
    report JSONB NOT NULL DEFAULT '{}'::jsonb,
    email_status TEXT,
    email_error TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    CONSTRAINT daily_job_exports_status_check CHECK (status IN ('running','succeeded','partial','failed'))
);

COMMIT;
