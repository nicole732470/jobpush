BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.job_title_ai_classifications (
    ai_classification_id BIGSERIAL PRIMARY KEY,
    normalized_title TEXT NOT NULL REFERENCES jobpush.job_title_labels(normalized_title) ON DELETE CASCADE,
    classification_status TEXT NOT NULL,
    canonical_role TEXT,
    confidence NUMERIC(5,4) NOT NULL,
    model_name TEXT NOT NULL,
    prompt_version TEXT NOT NULL,
    profile_version TEXT NOT NULL,
    input_hash TEXT NOT NULL,
    rationale TEXT,
    raw_response JSONB NOT NULL DEFAULT '{}'::jsonb,
    applied BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT job_title_ai_classifications_status_check
        CHECK (classification_status IN ('review', 'target', 'non_target')),
    CONSTRAINT job_title_ai_classifications_confidence_check
        CHECK (confidence >= 0 AND confidence <= 1)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_job_title_ai_classifications_input
    ON jobpush.job_title_ai_classifications(normalized_title, prompt_version, profile_version, model_name, input_hash);

CREATE INDEX IF NOT EXISTS idx_job_title_ai_classifications_apply
    ON jobpush.job_title_ai_classifications(applied, confidence DESC, created_at DESC);

CREATE OR REPLACE FUNCTION jobpush.apply_ai_job_title_classifications(
    p_min_target_confidence NUMERIC DEFAULT 0.88,
    p_min_non_target_confidence NUMERIC DEFAULT 0.84,
    p_limit INTEGER DEFAULT 500
) RETURNS TABLE(applied_count INTEGER, target_count INTEGER, non_target_count INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_applied INTEGER := 0;
    v_target INTEGER := 0;
    v_non_target INTEGER := 0;
BEGIN
    WITH latest AS (
        SELECT DISTINCT ON (ai.normalized_title)
               ai.ai_classification_id,
               ai.normalized_title,
               ai.classification_status,
               ai.canonical_role,
               ai.confidence,
               ai.model_name,
               ai.prompt_version,
               ai.profile_version,
               ai.rationale,
               label.classification_status AS previous_status,
               label.rule_version AS previous_rule_version
        FROM jobpush.job_title_ai_classifications ai
        JOIN jobpush.job_title_labels label USING (normalized_title)
        WHERE NOT ai.applied
          AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
          AND label.classification_status = 'review'
          AND (
              (ai.classification_status = 'target' AND ai.confidence >= p_min_target_confidence)
              OR (ai.classification_status = 'non_target' AND ai.confidence >= p_min_non_target_confidence)
          )
        ORDER BY ai.normalized_title, ai.created_at DESC, ai.confidence DESC
        LIMIT p_limit
    ), history_insert AS (
        INSERT INTO jobpush.job_title_label_history (
            normalized_title, previous_status, new_status, canonical_role,
            decision_reason, labeled_by
        )
        SELECT normalized_title,
               previous_status,
               classification_status,
               canonical_role,
               'ai_title_classifier: ' || coalesce(rationale, '') ||
                   ' confidence=' || confidence::text ||
                   ' prompt=' || prompt_version ||
                   ' profile=' || profile_version,
               'system:ai-title-classifier'
        FROM latest
        RETURNING normalized_title, new_status
    ), label_update AS (
        UPDATE jobpush.job_title_labels label
        SET classification_status = latest.classification_status,
            canonical_role = latest.canonical_role,
            rule_version = 'ai-title-classifier-v1',
            decision_reason = 'ai_title_classifier: ' || coalesce(latest.rationale, '') ||
                ' confidence=' || latest.confidence::text ||
                ' prompt=' || latest.prompt_version ||
                ' profile=' || latest.profile_version,
            labeled_by = 'system:ai-title-classifier',
            labeled_at = now(),
            updated_at = now()
        FROM latest
        WHERE label.normalized_title = latest.normalized_title
          AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
          AND label.classification_status = 'review'
        RETURNING label.normalized_title, label.classification_status
    ), ai_update AS (
        UPDATE jobpush.job_title_ai_classifications ai
        SET applied = TRUE
        FROM label_update
        WHERE ai.normalized_title = label_update.normalized_title
          AND NOT ai.applied
        RETURNING label_update.classification_status
    )
    SELECT count(*)::integer,
           count(*) FILTER (WHERE classification_status = 'target')::integer,
           count(*) FILTER (WHERE classification_status = 'non_target')::integer
    INTO v_applied, v_target, v_non_target
    FROM ai_update;

    RETURN QUERY SELECT v_applied, v_target, v_non_target;
END;
$$;

COMMENT ON TABLE jobpush.job_title_ai_classifications IS
    'Audited AI title classifications. Manual labels and deterministic profile rules remain higher precedence; only high-confidence AI decisions are applied.';

COMMIT;
