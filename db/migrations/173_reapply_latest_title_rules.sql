\set ON_ERROR_STOP on
\pset pager off

BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.title_rule_reconciliation_state (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    last_reconciled_term_id BIGINT NOT NULL
);

INSERT INTO jobpush.title_rule_reconciliation_state (
    singleton, last_reconciled_term_id
)
SELECT TRUE, COALESCE(max(term_id), 0)
FROM jobpush.profile_title_rule_terms
ON CONFLICT (singleton) DO NOTHING;

CREATE OR REPLACE FUNCTION jobpush.reapply_latest_profile_title_rules()
RETURNS TABLE(updated_titles INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_term_id BIGINT;
    v_this_term_id BIGINT;
    v_updated INTEGER;
BEGIN
    SELECT last_reconciled_term_id INTO v_last_term_id
    FROM jobpush.title_rule_reconciliation_state
    WHERE singleton
    FOR UPDATE;

    SELECT COALESCE(max(term_id), v_last_term_id) INTO v_this_term_id
    FROM jobpush.profile_title_rule_terms;

    DROP TABLE IF EXISTS pg_temp.latest_title_rule_changes;
    CREATE TEMP TABLE latest_title_rule_changes ON COMMIT DROP AS
    WITH changed_rules AS (
        SELECT *
        FROM jobpush.profile_title_rule_terms
        WHERE active
          AND rule_version = 'profile-title-rules-v2'
          AND term_id > v_last_term_id
          AND term_id <= v_this_term_id
    ), candidate_titles AS (
        SELECT label.normalized_title,
               label.classification_status AS previous_status,
               label.rule_version AS previous_rule_version,
               label.labeled_at,
               max(rule.created_at) AS newest_rule_at
        FROM jobpush.job_title_labels label
        JOIN changed_rules rule
          ON lower(label.normalized_title) ~ rule.regex_pattern
        GROUP BY label.normalized_title, label.classification_status,
                 label.rule_version, label.labeled_at
    ), proposed AS (
        SELECT candidate.*,
               CASE
                   WHEN candidate.normalized_title ~* '(^|[^a-z])forward[ -]+deployed([^a-z]|$)'
                       THEN 'target'
                   ELSE decision.classification_status
               END AS new_status,
               CASE
                   WHEN candidate.normalized_title ~* '(^|[^a-z])forward[ -]+deployed([^a-z]|$)'
                       THEN 'candidate_profile_track: applied_ai'
                   ELSE decision.canonical_role
               END AS canonical_role,
               CASE
                   WHEN candidate.normalized_title ~* '(^|[^a-z])forward[ -]+deployed([^a-z]|$)'
                       THEN 'profile_target_forward_deployed'
                   ELSE decision.decision_reason
               END AS decision_reason
        FROM candidate_titles candidate
        CROSS JOIN LATERAL jobpush.profile_title_rule_decision(candidate.normalized_title) decision
    )
    SELECT *
    FROM proposed
    WHERE new_status IN ('target', 'non_target')
      AND previous_status IS DISTINCT FROM new_status
      AND (
          COALESCE(previous_rule_version, '') NOT LIKE 'manual%'
          OR newest_rule_at > labeled_at
      );

    INSERT INTO jobpush.job_title_label_history (
        normalized_title, previous_status, new_status, canonical_role,
        decision_reason, labeled_by
    )
    SELECT normalized_title, previous_status, new_status, canonical_role,
           decision_reason || ': latest profile rule reconciliation',
           'system:latest-profile-rules'
    FROM latest_title_rule_changes;

    UPDATE jobpush.job_title_labels label
    SET classification_status = change.new_status,
        canonical_role = change.canonical_role,
        rule_version = 'profile-title-rules-v2',
        decision_reason = change.decision_reason || ': latest profile rule reconciliation',
        labeled_by = 'system:latest-profile-rules',
        labeled_at = now(),
        updated_at = now()
    FROM latest_title_rule_changes change
    WHERE label.normalized_title = change.normalized_title;

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    UPDATE jobpush.job_title_ml_classifications ml
    SET applied = FALSE
    FROM latest_title_rule_changes change
    WHERE ml.normalized_title = change.normalized_title
      AND ml.applied;

    UPDATE jobpush.title_rule_reconciliation_state
    SET last_reconciled_term_id = v_this_term_id
    WHERE singleton;

    RETURN QUERY SELECT v_updated;
END;
$$;

COMMIT;
