\set ON_ERROR_STOP on
\pset pager off

BEGIN;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES (
    'profile-title-rules-v2', '2026-07-13-draft-6', 'target',
    'candidate_profile_track: applied_ai', 'forward deployed roles',
    '(^|[^a-z])forward[ -]+deployed([^a-z]|$)',
    'candidate_profile.tracks.ai_eng', 'profile_target_forward_deployed', 1, TRUE
)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE OR REPLACE FUNCTION jobpush.apply_profile_title_boundary()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_decision RECORD;
BEGIN
    IF COALESCE(NEW.rule_version, '') LIKE 'manual%%' THEN
        RETURN NEW;
    END IF;

    IF NEW.normalized_title ~* '(^|[^a-z])forward[ -]+deployed([^a-z]|$)' THEN
        NEW.classification_status := 'target';
        NEW.canonical_role := 'candidate_profile_track: applied_ai';
        NEW.rule_version := 'profile-title-rules-v2';
        NEW.decision_reason := 'profile_target_forward_deployed: candidate_profile 2026-07-13';
        NEW.labeled_by := 'system:profile-title-rules-v2';
        NEW.labeled_at := now();
        NEW.updated_at := now();
        RETURN NEW;
    END IF;

    SELECT * INTO v_decision
    FROM jobpush.profile_title_rule_decision(NEW.normalized_title)
    LIMIT 1;

    IF v_decision.classification_status IN ('target', 'non_target') THEN
        NEW.classification_status := v_decision.classification_status;
        NEW.canonical_role := v_decision.canonical_role;
        NEW.rule_version := 'profile-title-rules-v2';
        NEW.decision_reason := v_decision.decision_reason || ': candidate_profile 2026-07-13';
        NEW.labeled_by := 'system:profile-title-rules-v2';
        NEW.labeled_at := now();
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TEMP TABLE forward_deployed_updates ON COMMIT DROP AS
SELECT normalized_title, classification_status AS previous_status
FROM jobpush.job_title_labels
WHERE normalized_title ~* '(^|[^a-z])forward[ -]+deployed([^a-z]|$)';

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, 'target',
       'candidate_profile_track: applied_ai',
       'profile_target_forward_deployed: candidate_profile 2026-07-13',
       'system:profile-title-rules-v2'
FROM forward_deployed_updates
WHERE previous_status IS DISTINCT FROM 'target';

UPDATE jobpush.job_title_labels label
SET classification_status = 'target',
    canonical_role = 'candidate_profile_track: applied_ai',
    rule_version = 'profile-title-rules-v2',
    decision_reason = 'profile_target_forward_deployed: candidate_profile 2026-07-13',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM forward_deployed_updates update_set
WHERE label.normalized_title = update_set.normalized_title;

COMMIT;

SELECT classification_status, count(*) AS titles
FROM jobpush.job_title_labels
WHERE normalized_title ~* '(^|[^a-z])forward[ -]+deployed([^a-z]|$)'
GROUP BY 1;
