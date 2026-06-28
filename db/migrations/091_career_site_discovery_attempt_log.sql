BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.career_site_discovery_attempts (
    discovery_attempt_id BIGSERIAL PRIMARY KEY,
    run_id TEXT NOT NULL REFERENCES jobpush.career_site_discovery_runs(run_id) ON DELETE CASCADE,
    cohort TEXT,
    consolidation_key TEXT NOT NULL REFERENCES jobpush.crawl_targets(consolidation_key) ON DELETE CASCADE,
    canonical_name TEXT NOT NULL,
    priority_tier TEXT,
    priority_score NUMERIC,
    search_query TEXT NOT NULL,
    search_succeeded BOOLEAN NOT NULL,
    candidate_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT career_site_discovery_attempts_candidate_count_check
        CHECK (candidate_count >= 0),
    UNIQUE (run_id, consolidation_key)
);

CREATE INDEX IF NOT EXISTS idx_career_site_discovery_attempts_company
    ON jobpush.career_site_discovery_attempts(consolidation_key, attempted_at DESC);

CREATE INDEX IF NOT EXISTS idx_career_site_discovery_attempts_error
    ON jobpush.career_site_discovery_attempts(search_succeeded, attempted_at DESC)
    WHERE NOT search_succeeded;

CREATE OR REPLACE VIEW jobpush.career_site_discovery_attempt_summary AS
WITH run_rollup AS (
    SELECT
        run_id,
        cohort,
        COUNT(*) AS companies,
        COUNT(*) FILTER (WHERE search_succeeded) AS succeeded_searches,
        COUNT(*) FILTER (WHERE search_succeeded AND candidate_count > 0) AS searches_with_candidates,
        COUNT(*) FILTER (WHERE search_succeeded AND candidate_count = 0) AS searched_no_candidate,
        COUNT(*) FILTER (WHERE NOT search_succeeded) AS failed_searches,
        COUNT(*) FILTER (
            WHERE NOT search_succeeded
              AND (
                  error_message ILIKE 'HTTPError: HTTP Error 429%%'
                  OR error_message ILIKE 'HTTPError: HTTP Error 432%%'
                  OR error_message ILIKE 'HTTPError: HTTP Error 5%%'
                  OR error_message ILIKE 'URLError%%'
                  OR error_message ILIKE 'TimeoutError%%'
              )
        ) AS transient_failures,
        MIN(attempted_at) AS first_attempted_at,
        MAX(attempted_at) AS last_attempted_at
    FROM jobpush.career_site_discovery_attempts
    GROUP BY run_id, cohort
)
SELECT
    *,
    CASE
        WHEN companies > 0 AND failed_searches = companies THEN 'full_batch_failed'
        WHEN failed_searches > 0 THEN 'partial_failures'
        WHEN searched_no_candidate > 0 THEN 'completed_with_no_candidate'
        ELSE 'completed_with_candidates'
    END AS run_quality
FROM run_rollup;

COMMENT ON TABLE jobpush.career_site_discovery_attempts IS
    'Per-company Tavily career-site search audit. Normal expansion should search never-searched companies only; retry rows are reset only for provider/network batch failures.';

COMMENT ON VIEW jobpush.career_site_discovery_attempt_summary IS
    'Run-level quality summary used to distinguish full provider/network failure from ordinary no-candidate or partial failures.';

COMMIT;
