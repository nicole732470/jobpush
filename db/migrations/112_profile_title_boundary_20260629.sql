BEGIN;

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

    SELECT * INTO v_decision
    FROM jobpush.profile_title_rule_decision(NEW.normalized_title)
    LIMIT 1;

    IF v_decision.classification_status IN ('target', 'non_target') THEN
        NEW.classification_status := v_decision.classification_status;
        NEW.canonical_role := v_decision.canonical_role;
        NEW.rule_version := 'profile-title-rules-v2';
        NEW.decision_reason := v_decision.decision_reason || ': candidate_profile 2026-06-29';
        NEW.labeled_by := 'system:profile-title-rules-v2';
        NEW.labeled_at := now();
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;

COMMIT;
