BEGIN;

-- Follow-up to migration 089: the leakage audit found a small residual set of
-- Latin-script non-US and joined leadership terms still reaching review.

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-8',
        'non_target',
        NULL,
        'joined leadership terms',
        '(^|[^a-z])(teamleader|shiftlead|shift leader|future leaders|r d leaders)([^a-z]|$)',
        'title_review_leak_audit_2026-06-28',
        'profile_hard_joined_leadership_exclusion',
        10,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-8',
        'non_target',
        NULL,
        'latin script non us title markers',
        '(^|[^a-z])(m/w/d|técnico|tecnico|solicitud|empleado temporal|verkauf|vietnam)([^a-z]|$)',
        'title_review_leak_audit_2026-06-28',
        'profile_non_us_latin_language_marker',
        12,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-8',
        'non_target',
        NULL,
        'business development executive',
        '(^|[^a-z])(business development executive)([^a-z]|$)',
        'title_review_leak_audit_2026-06-28',
        'profile_avoid_business_development_executive',
        18,
        TRUE
    )
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

WITH proposed AS (
    SELECT
        label.normalized_title,
        label.classification_status AS previous_status,
        'non_target'::text AS new_status,
        NULL::text AS canonical_role,
        CASE
            WHEN label.normalized_title ~* '(^|[^a-z])(teamleader|shiftlead|shift leader|future leaders|r d leaders)([^a-z]|$)'
                THEN 'profile_hard_joined_leadership_exclusion'
            WHEN label.normalized_title ~* '(^|[^a-z])(m/w/d|técnico|tecnico|solicitud|empleado temporal|verkauf|vietnam)([^a-z]|$)'
                THEN 'profile_non_us_latin_language_marker'
            WHEN label.normalized_title ~* '(^|[^a-z])(business development executive)([^a-z]|$)'
                THEN 'profile_avoid_business_development_executive'
        END AS decision_reason
    FROM jobpush.job_title_labels label
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND (
          label.normalized_title ~* '(^|[^a-z])(teamleader|shiftlead|shift leader|future leaders|r d leaders)([^a-z]|$)'
          OR label.normalized_title ~* '(^|[^a-z])(m/w/d|técnico|tecnico|solicitud|empleado temporal|verkauf|vietnam)([^a-z]|$)'
          OR label.normalized_title ~* '(^|[^a-z])(business development executive)([^a-z]|$)'
      )
      AND (label.classification_status IS DISTINCT FROM 'non_target'
           OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
           OR label.canonical_role IS NOT NULL
           OR label.decision_reason IS DISTINCT FROM
              CASE
                  WHEN label.normalized_title ~* '(^|[^a-z])(teamleader|shiftlead|shift leader|future leaders|r d leaders)([^a-z]|$)'
                      THEN 'profile_hard_joined_leadership_exclusion: candidate_profile 2026-06-28'
                  WHEN label.normalized_title ~* '(^|[^a-z])(m/w/d|técnico|tecnico|solicitud|empleado temporal|verkauf|vietnam)([^a-z]|$)'
                      THEN 'profile_non_us_latin_language_marker: candidate_profile 2026-06-28'
                  WHEN label.normalized_title ~* '(^|[^a-z])(business development executive)([^a-z]|$)'
                      THEN 'profile_avoid_business_development_executive: candidate_profile 2026-06-28'
              END)
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-06-28',
       'system:profile-title-rules-v2'
FROM proposed;

WITH proposed AS (
    SELECT
        label.normalized_title,
        'non_target'::text AS new_status,
        NULL::text AS canonical_role,
        CASE
            WHEN label.normalized_title ~* '(^|[^a-z])(teamleader|shiftlead|shift leader|future leaders|r d leaders)([^a-z]|$)'
                THEN 'profile_hard_joined_leadership_exclusion'
            WHEN label.normalized_title ~* '(^|[^a-z])(m/w/d|técnico|tecnico|solicitud|empleado temporal|verkauf|vietnam)([^a-z]|$)'
                THEN 'profile_non_us_latin_language_marker'
            WHEN label.normalized_title ~* '(^|[^a-z])(business development executive)([^a-z]|$)'
                THEN 'profile_avoid_business_development_executive'
        END AS decision_reason
    FROM jobpush.job_title_labels label
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND (
          label.normalized_title ~* '(^|[^a-z])(teamleader|shiftlead|shift leader|future leaders|r d leaders)([^a-z]|$)'
          OR label.normalized_title ~* '(^|[^a-z])(m/w/d|técnico|tecnico|solicitud|empleado temporal|verkauf|vietnam)([^a-z]|$)'
          OR label.normalized_title ~* '(^|[^a-z])(business development executive)([^a-z]|$)'
      )
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = proposed.decision_reason || ': candidate_profile 2026-06-28',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM proposed
WHERE label.normalized_title = proposed.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

UPDATE jobpush.job_title_ml_classifications prediction
SET applied = FALSE
FROM jobpush.job_title_labels label
WHERE prediction.normalized_title = label.normalized_title
  AND label.classification_status = 'non_target'
  AND (
      label.decision_reason LIKE 'profile_hard_joined_leadership_exclusion%%'
      OR label.decision_reason LIKE 'profile_non_us_latin_language_marker%%'
      OR label.decision_reason LIKE 'profile_avoid_business_development_executive%%'
  );

COMMIT;

SELECT classification_status, rule_version, decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_hard_joined_leadership_exclusion%%'
   OR decision_reason LIKE 'profile_non_us_latin_language_marker%%'
   OR decision_reason LIKE 'profile_avoid_business_development_executive%%'
GROUP BY 1, 2, 3
ORDER BY titles DESC;
