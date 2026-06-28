BEGIN;

-- Nicole profile update, 2026-06-27:
-- Senior titles are out of scope for JobPush recommendations.
-- This supersedes the previous narrower "senior SDE only" exclusion.

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES (
    'profile-title-rules-v2',
    '2026-06-27-draft-5',
    'non_target',
    NULL,
    'senior all roles',
    '(^|[^a-z])(senior|sr\.?)([^a-z]|$)',
    'candidate_profile.seniority_policy updated 2026-06-27',
    'profile_avoid_all_senior_titles',
    9,
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
    SELECT label.normalized_title,
           label.classification_status AS previous_status,
           'non_target'::text AS new_status,
           NULL::text AS canonical_role,
           'profile_avoid_all_senior_titles: candidate_profile 2026-06-27'::text AS decision_reason
    FROM jobpush.job_title_labels label
    WHERE lower(label.normalized_title) ~ '(^|[^a-z])(senior|sr\.?)([^a-z]|$)'
      AND (
          label.classification_status IS DISTINCT FROM 'non_target'
          OR label.canonical_role IS NOT NULL
          OR label.decision_reason IS DISTINCT FROM 'profile_avoid_all_senior_titles: candidate_profile 2026-06-27'
      )
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason, 'system:profile-title-rules-v2'
FROM proposed;

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'profile-title-rules-v2',
    decision_reason = 'profile_avoid_all_senior_titles: candidate_profile 2026-06-27',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
WHERE lower(label.normalized_title) ~ '(^|[^a-z])(senior|sr\.?)([^a-z]|$)';

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
WHERE lower(ml.normalized_title) ~ '(^|[^a-z])(senior|sr\.?)([^a-z]|$)';

COMMIT;
