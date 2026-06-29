BEGIN;

ALTER TABLE jobpush.job_application_actions
    DROP CONSTRAINT IF EXISTS job_application_actions_status_check;

ALTER TABLE jobpush.job_application_actions
    ADD CONSTRAINT job_application_actions_status_check
    CHECK (action_status IN ('saved', 'apply_next', 'referred', 'applied', 'dismissed'));

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
    IF p_action_status NOT IN ('saved', 'apply_next', 'referred', 'applied', 'dismissed') THEN
        RAISE EXCEPTION 'Status must be saved, apply_next, referred, applied, or dismissed';
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

SELECT action_status, count(*) AS actions
FROM jobpush.job_application_actions
GROUP BY action_status
ORDER BY action_status;

COMMIT;
