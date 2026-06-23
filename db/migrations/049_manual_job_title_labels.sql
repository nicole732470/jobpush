BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.job_title_label_history (
    history_id BIGSERIAL PRIMARY KEY,
    normalized_title TEXT NOT NULL,
    previous_status TEXT,
    new_status TEXT NOT NULL,
    canonical_role TEXT,
    decision_reason TEXT,
    labeled_by TEXT NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT job_title_label_history_status_check
        CHECK (new_status IN ('review', 'target', 'non_target'))
);

CREATE INDEX IF NOT EXISTS idx_job_title_label_history_title_changed
    ON jobpush.job_title_label_history(normalized_title, changed_at DESC);

CREATE OR REPLACE FUNCTION jobpush.apply_manual_job_title_label(
    p_normalized_title TEXT,
    p_status TEXT,
    p_canonical_role TEXT,
    p_reason TEXT,
    p_labeled_by TEXT DEFAULT 'nicole'
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_previous_status TEXT;
BEGIN
    IF p_status NOT IN ('review', 'target', 'non_target') THEN
        RAISE EXCEPTION 'Invalid classification status: %', p_status;
    END IF;
    IF NULLIF(btrim(p_normalized_title), '') IS NULL THEN
        RAISE EXCEPTION 'normalized_title is required';
    END IF;

    SELECT classification_status INTO v_previous_status
    FROM jobpush.job_title_labels
    WHERE normalized_title = p_normalized_title;

    INSERT INTO jobpush.job_title_labels (
        normalized_title, classification_status, canonical_role, rule_version,
        decision_reason, labeled_by, labeled_at, updated_at
    ) VALUES (
        p_normalized_title, p_status, NULLIF(btrim(p_canonical_role), ''),
        'manual-v1', NULLIF(btrim(p_reason), ''), p_labeled_by, now(), now()
    )
    ON CONFLICT (normalized_title) DO UPDATE SET
        classification_status = EXCLUDED.classification_status,
        canonical_role = EXCLUDED.canonical_role,
        rule_version = EXCLUDED.rule_version,
        decision_reason = EXCLUDED.decision_reason,
        labeled_by = EXCLUDED.labeled_by,
        labeled_at = EXCLUDED.labeled_at,
        updated_at = now();

    INSERT INTO jobpush.job_title_label_history (
        normalized_title, previous_status, new_status, canonical_role,
        decision_reason, labeled_by
    ) VALUES (
        p_normalized_title, v_previous_status, p_status,
        NULLIF(btrim(p_canonical_role), ''), NULLIF(btrim(p_reason), ''), p_labeled_by
    );
END;
$$;

COMMIT;
