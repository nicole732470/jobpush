BEGIN;

-- ponytail: keep the senior hard-exclude; only PM-family titles get the exception.
CREATE OR REPLACE FUNCTION jobpush.profile_title_rule_decision(p_title TEXT)
RETURNS TABLE(classification_status TEXT, canonical_role TEXT, decision_reason TEXT)
LANGUAGE sql
STABLE
AS $$
    WITH title AS (
        SELECT lower(coalesce(p_title, '')) AS value
    ), language_signal AS (
        SELECT 1 AS hit
        FROM title
        WHERE value ~ '([ぁ-ゟァ-ヿ가-힣]|日本語|韓国|한국|서울)'
        LIMIT 1
    ), pm_senior_exception AS (
        SELECT 1 AS hit
        FROM title
        WHERE value ~ '(^|[^a-z])(senior|sr\.?)([^a-z]|$)'
          AND value ~ '(^|[^a-z])((technical[ -]+)?product manager|product owner|program manager|project manager)([^a-z]|$)'
        LIMIT 1
    ), first_non_target AS (
        SELECT term.canonical_role, term.decision_reason
        FROM title
        JOIN jobpush.profile_title_rule_terms term
          ON term.active
         AND term.rule_version = 'profile-title-rules-v2'
         AND term.rule_type = 'non_target'
         AND title.value ~ term.regex_pattern
         AND NOT (
             term.decision_reason = 'profile_avoid_all_senior_titles'
             AND EXISTS (SELECT 1 FROM pm_senior_exception)
         )
        ORDER BY term.priority, length(term.term) DESC, term.term
        LIMIT 1
    ), first_target AS (
        SELECT term.canonical_role, term.decision_reason
        FROM title
        JOIN jobpush.profile_title_rule_terms term
          ON term.active
         AND term.rule_version = 'profile-title-rules-v2'
         AND term.rule_type = 'target'
         AND title.value ~ term.regex_pattern
        ORDER BY term.priority, length(term.term) DESC, term.term
        LIMIT 1
    ), chosen_target AS (
        SELECT canonical_role, decision_reason FROM first_target
        UNION ALL
        SELECT 'candidate_profile_track: product', 'profile_target_pm_senior_exception'
        FROM pm_senior_exception
        LIMIT 1
    )
    SELECT
        CASE
            WHEN EXISTS (SELECT 1 FROM language_signal) THEN 'non_target'
            WHEN EXISTS (SELECT 1 FROM first_non_target) THEN 'non_target'
            WHEN EXISTS (SELECT 1 FROM chosen_target) THEN 'target'
            ELSE 'review'
        END AS classification_status,
        CASE
            WHEN EXISTS (SELECT 1 FROM chosen_target) AND NOT EXISTS (SELECT 1 FROM language_signal) AND NOT EXISTS (SELECT 1 FROM first_non_target)
                THEN (SELECT canonical_role FROM chosen_target)
            ELSE NULL
        END AS canonical_role,
        CASE
            WHEN EXISTS (SELECT 1 FROM language_signal) THEN 'profile_non_us_language_signal'
            WHEN EXISTS (SELECT 1 FROM first_non_target) THEN (SELECT decision_reason FROM first_non_target)
            WHEN EXISTS (SELECT 1 FROM chosen_target) THEN (SELECT decision_reason FROM chosen_target)
            ELSE 'profile_no_rule_match'
        END AS decision_reason;
$$;

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
        NEW.decision_reason := v_decision.decision_reason || ': candidate_profile 2026-07-01';
        NEW.labeled_by := 'system:profile-title-rules-v2';
        NEW.labeled_at := now();
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TEMP TABLE senior_pm_updates ON COMMIT DROP AS
SELECT label.normalized_title,
       label.classification_status AS previous_status,
       decision.classification_status AS new_status,
       decision.canonical_role,
       decision.decision_reason
FROM jobpush.job_title_labels label
CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
  AND decision.classification_status = 'target'
  AND label.normalized_title ~* '(^|[^a-z])(senior|sr\.?)([^a-z]|$)'
  AND label.normalized_title ~* '(^|[^a-z])((technical[ -]+)?product manager|product owner|program manager|project manager)([^a-z]|$)';

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-07-01',
       'system:profile-title-rules-v2'
FROM senior_pm_updates;

UPDATE jobpush.job_title_labels label
SET classification_status = senior_pm_updates.new_status,
    canonical_role = senior_pm_updates.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = senior_pm_updates.decision_reason || ': candidate_profile 2026-07-01',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM senior_pm_updates
WHERE label.normalized_title = senior_pm_updates.normalized_title;

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM senior_pm_updates
WHERE ml.normalized_title = senior_pm_updates.normalized_title;

COMMIT;

SELECT classification_status, canonical_role, decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE normalized_title ~* '(^|[^a-z])(senior|sr\.?)([^a-z]|$)'
  AND normalized_title ~* '(^|[^a-z])((technical[ -]+)?product manager|product owner|program manager|project manager)([^a-z]|$)'
GROUP BY 1, 2, 3
ORDER BY titles DESC;
