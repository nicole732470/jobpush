BEGIN;

CREATE SCHEMA IF NOT EXISTS jobpush;

CREATE TABLE IF NOT EXISTS jobpush.company_targets (
    fein                    TEXT PRIMARY KEY
                            REFERENCES public.companies(fein) ON DELETE CASCADE,
    company_id              BIGINT NOT NULL,
    company_name            TEXT NOT NULL,
    naics_code              TEXT,
    naics_sector            TEXT,
    employer_city           TEXT,
    employer_state          TEXT,
    lca_count               INTEGER NOT NULL DEFAULT 0,
    certified_count         INTEGER NOT NULL DEFAULT 0,
    single_lca_company      BOOLEAN NOT NULL DEFAULT FALSE,
    target_role_match       BOOLEAN NOT NULL DEFAULT FALSE,
    target_role_lca_count   INTEGER NOT NULL DEFAULT 0,
    last_decision_date      DATE,
    priority_score          INTEGER NOT NULL DEFAULT 0,
    priority_version        TEXT NOT NULL DEFAULT 'v1',
    crawl_status            TEXT NOT NULL DEFAULT 'pending',
    last_crawled_at         TIMESTAMPTZ,
    next_crawl_at           TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (priority_score >= 0),
    CHECK (crawl_status IN ('pending', 'queued', 'crawling', 'complete', 'failed', 'paused'))
);

CREATE INDEX IF NOT EXISTS idx_jobpush_targets_priority
    ON jobpush.company_targets(priority_score DESC, last_decision_date DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_jobpush_targets_status
    ON jobpush.company_targets(crawl_status, priority_score DESC);
CREATE INDEX IF NOT EXISTS idx_jobpush_targets_sector
    ON jobpush.company_targets(naics_sector);

COMMIT;
