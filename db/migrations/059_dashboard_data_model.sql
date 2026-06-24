BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.job_application_actions (
    site_id BIGINT NOT NULL,
    external_job_id TEXT NOT NULL,
    action_status TEXT NOT NULL,
    notes TEXT,
    changed_by TEXT NOT NULL DEFAULT 'nicole',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, external_job_id),
    CONSTRAINT job_application_actions_posting_fk
        FOREIGN KEY (site_id, external_job_id)
        REFERENCES jobpush.job_postings(site_id, external_job_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT job_application_actions_status_check
        CHECK (action_status IN ('saved', 'apply_next', 'applied', 'dismissed'))
);

CREATE INDEX IF NOT EXISTS idx_job_application_actions_status_updated
    ON jobpush.job_application_actions(action_status, updated_at DESC);

CREATE OR REPLACE FUNCTION jobpush.set_job_application_action(
    p_site_id BIGINT,
    p_external_job_id TEXT,
    p_action_status TEXT,
    p_notes TEXT DEFAULT NULL,
    p_changed_by TEXT DEFAULT 'nicole'
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_action_status NOT IN ('saved', 'apply_next', 'applied', 'dismissed') THEN
        RAISE EXCEPTION 'Status must be saved, apply_next, applied, or dismissed';
    END IF;

    INSERT INTO jobpush.job_application_actions (
        site_id, external_job_id, action_status, notes, changed_by
    ) VALUES (
        p_site_id, p_external_job_id, p_action_status,
        NULLIF(btrim(p_notes), ''), p_changed_by
    )
    ON CONFLICT (site_id, external_job_id) DO UPDATE SET
        action_status = EXCLUDED.action_status,
        notes = EXCLUDED.notes,
        changed_by = EXCLUDED.changed_by,
        updated_at = now();
END;
$$;

CREATE OR REPLACE VIEW jobpush.dashboard_crawl_funnel AS
SELECT
    (SELECT count(*) FROM jobpush.company_targets_consolidated) AS all_companies,
    (SELECT count(*) FROM jobpush.company_targets_consolidated WHERE target_role_score = 1) AS target_soc_companies,
    (SELECT count(*) FROM jobpush.company_targets_consolidated WHERE crawl_priority_tier = 'P0') AS p0_companies,
    (SELECT count(*) FROM jobpush.company_targets_consolidated WHERE crawl_priority_tier = 'P1') AS p1_companies,
    (SELECT count(*) FROM jobpush.company_targets_consolidated WHERE crawl_priority_tier = 'P2') AS p2_companies,
    (SELECT count(*) FROM jobpush.crawl_targets WHERE enabled) AS enabled_targets,
    (SELECT count(DISTINCT consolidation_key) FROM jobpush.career_sites WHERE verification_status = 'unverified') AS companies_with_candidates,
    (SELECT count(DISTINCT consolidation_key) FROM jobpush.career_sites WHERE verification_status = 'verified') AS companies_with_verified_site,
    (SELECT count(*) FROM jobpush.career_sites WHERE verification_status = 'verified' AND target_country_code = 'US' AND scope_method <> 'unknown') AS us_ready_sites,
    (SELECT count(*) FROM jobpush.career_sites WHERE verification_status = 'verified' AND source_type IN ('apple_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday')) AS adapter_supported_sites,
    (SELECT count(*) FROM jobpush.crawl_schedule_queue) AS schedulable_sites,
    (SELECT count(*) FROM jobpush.crawl_schedule_queue WHERE is_due) AS due_sites,
    (SELECT count(*) FROM jobpush.crawl_schedule_queue WHERE last_crawled_at IS NULL) AS never_crawled_schedulable_sites;

CREATE OR REPLACE VIEW jobpush.dashboard_jobs AS
SELECT
    posting.site_id,
    posting.external_job_id,
    posting.consolidation_key,
    target.canonical_name,
    target.priority_tier,
    posting.title,
    posting.normalized_title,
    posting.location,
    posting.category,
    posting.employment_type,
    COALESCE(label.classification_status, 'review') AS role_status,
    label.canonical_role,
    COALESCE(action.action_status, 'new') AS application_status,
    action.notes AS application_notes,
    posting.posted_text,
    posting.first_seen_at,
    posting.last_seen_at,
    posting.job_url
FROM jobpush.job_postings_us posting
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
LEFT JOIN jobpush.job_application_actions action
  ON action.site_id = posting.site_id
 AND action.external_job_id = posting.external_job_id;

CREATE OR REPLACE VIEW jobpush.dashboard_daily_activity AS
WITH days AS (
    SELECT generate_series(
        (current_date - 29)::timestamp,
        current_date::timestamp,
        interval '1 day'
    )::date AS activity_date
), jobs AS (
    SELECT
        (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date AS activity_date,
        count(*) AS new_jobs,
        count(*) FILTER (WHERE COALESCE(label.classification_status, 'review') = 'target') AS new_target_jobs,
        count(*) FILTER (WHERE COALESCE(label.classification_status, 'review') = 'review') AS new_review_jobs
    FROM jobpush.job_postings posting
    LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
    GROUP BY 1
), closed AS (
    SELECT
        (closed_at AT TIME ZONE 'America/Chicago')::date AS activity_date,
        count(*) AS closed_jobs
    FROM jobpush.job_postings
    WHERE closed_at IS NOT NULL
    GROUP BY 1
), runs AS (
    SELECT
        (started_at AT TIME ZONE 'America/Chicago')::date AS activity_date,
        count(*) AS crawl_runs,
        count(*) FILTER (WHERE status = 'succeeded') AS successful_runs,
        count(*) FILTER (WHERE status = 'failed') AS failed_runs,
        COALESCE(sum(requests_count), 0) AS requests,
        COALESCE(sum(new_job_count), 0) AS run_reported_new_jobs
    FROM jobpush.crawl_runs
    GROUP BY 1
)
SELECT
    days.activity_date,
    COALESCE(jobs.new_jobs, 0) AS new_jobs,
    COALESCE(jobs.new_target_jobs, 0) AS new_target_jobs,
    COALESCE(jobs.new_review_jobs, 0) AS new_review_jobs,
    COALESCE(closed.closed_jobs, 0) AS closed_jobs,
    COALESCE(runs.crawl_runs, 0) AS crawl_runs,
    COALESCE(runs.successful_runs, 0) AS successful_runs,
    COALESCE(runs.failed_runs, 0) AS failed_runs,
    COALESCE(runs.requests, 0) AS requests,
    COALESCE(runs.run_reported_new_jobs, 0) AS run_reported_new_jobs
FROM days
LEFT JOIN jobs USING (activity_date)
LEFT JOIN closed USING (activity_date)
LEFT JOIN runs USING (activity_date)
ORDER BY days.activity_date DESC;

COMMENT ON VIEW jobpush.dashboard_crawl_funnel IS
    'Company-to-schedulable-site funnel used by the private JobPush dashboard.';
COMMENT ON VIEW jobpush.dashboard_jobs IS
    'Active US jobs with title classification and personal application state.';
COMMENT ON VIEW jobpush.dashboard_daily_activity IS
    'Thirty days of Chicago-local crawl and job-change metrics.';

COMMIT;
