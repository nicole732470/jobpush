BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.job_title_ml_classifications (
    ml_classification_id BIGSERIAL PRIMARY KEY,
    normalized_title TEXT NOT NULL
        REFERENCES jobpush.job_title_labels(normalized_title) ON DELETE CASCADE,
    classification_status TEXT NOT NULL,
    confidence NUMERIC(6,5) NOT NULL,
    model_version TEXT NOT NULL,
    training_label_count INTEGER NOT NULL,
    holdout_precision NUMERIC(6,5),
    holdout_threshold NUMERIC(6,5),
    evidence_features TEXT[] NOT NULL DEFAULT '{}',
    metrics JSONB NOT NULL DEFAULT '{}'::jsonb,
    applied BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT job_title_ml_status_check
        CHECK (classification_status IN ('target', 'non_target')),
    CONSTRAINT job_title_ml_confidence_check CHECK (confidence BETWEEN 0 AND 1),
    UNIQUE (normalized_title, model_version)
);

CREATE INDEX IF NOT EXISTS idx_job_title_ml_apply
    ON jobpush.job_title_ml_classifications(applied, confidence DESC);

CREATE OR REPLACE FUNCTION jobpush.apply_local_job_title_ml(
    p_model_version TEXT,
    p_limit INTEGER DEFAULT 10000
) RETURNS TABLE(applied_count INTEGER, target_count INTEGER, non_target_count INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH eligible AS (
        SELECT ml.ml_classification_id, ml.normalized_title,
               ml.classification_status, ml.confidence,
               ml.model_version, ml.evidence_features,
               label.classification_status AS previous_status
        FROM jobpush.job_title_ml_classifications ml
        JOIN jobpush.job_title_labels label USING (normalized_title)
        WHERE ml.model_version = p_model_version
          AND NOT ml.applied
          AND label.classification_status = 'review'
          AND coalesce(label.rule_version, '') NOT LIKE 'manual%%'
        ORDER BY ml.confidence DESC
        LIMIT p_limit
    ), history AS (
        INSERT INTO jobpush.job_title_label_history (
            normalized_title, previous_status, new_status, canonical_role,
            decision_reason, labeled_by
        )
        SELECT normalized_title, previous_status, classification_status, NULL,
               'local_title_ml confidence=' || confidence::text ||
               ' evidence=' || array_to_string(evidence_features, ', '),
               'system:local-title-ml'
        FROM eligible
        RETURNING normalized_title
    ), updated AS (
        UPDATE jobpush.job_title_labels label
        SET classification_status = eligible.classification_status,
            canonical_role = NULL,
            rule_version = eligible.model_version,
            decision_reason = 'local_title_ml confidence=' || eligible.confidence::text ||
                ' evidence=' || array_to_string(eligible.evidence_features, ', '),
            labeled_by = 'system:local-title-ml',
            labeled_at = now(), updated_at = now()
        FROM eligible
        WHERE label.normalized_title = eligible.normalized_title
          AND label.classification_status = 'review'
          AND coalesce(label.rule_version, '') NOT LIKE 'manual%%'
        RETURNING label.normalized_title, label.classification_status
    ), marked AS (
        UPDATE jobpush.job_title_ml_classifications ml
        SET applied = TRUE
        FROM updated
        WHERE ml.normalized_title = updated.normalized_title
          AND ml.model_version = p_model_version
        RETURNING updated.classification_status
    )
    SELECT count(*)::INTEGER,
           count(*) FILTER (WHERE classification_status = 'target')::INTEGER,
           count(*) FILTER (WHERE classification_status = 'non_target')::INTEGER
    FROM marked;
END;
$$;

COMMENT ON TABLE jobpush.job_title_ml_classifications IS
    'Offline supervised word n-gram model predictions trained only from audited manual labels; no external model API.';

COMMIT;
