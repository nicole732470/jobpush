\pset pager off

BEGIN;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES (
    'profile-title-rules-v2','2026-07-13-draft-22','non_target',NULL,
    'project and program management roles',
    '(^|[^a-z])(project manager|program manager|project management|program management)([^a-z]|$)',
    'candidate_profile.avoid_tracks.project_program_management',
    'profile_avoid_project_program_management_roles',6,TRUE
)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE manager_exclusions ON COMMIT DROP AS
SELECT normalized_title, classification_status AS previous_status
FROM jobpush.job_title_labels
WHERE lower(normalized_title) ~ '(^|[^a-z])(project manager|program manager|project management|program management)([^a-z]|$)';

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, 'non_target', NULL,
       'profile_avoid_project_program_management_roles: candidate_profile 2026-07-13',
       'nicole'
FROM manager_exclusions
WHERE previous_status IS DISTINCT FROM 'non_target';

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'profile-title-rules-v2',
    decision_reason = 'profile_avoid_project_program_management_roles: candidate_profile 2026-07-13',
    labeled_by = 'nicole',
    labeled_at = now(),
    updated_at = now()
FROM manager_exclusions exclusion
WHERE label.normalized_title = exclusion.normalized_title;

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM manager_exclusions exclusion
WHERE ml.normalized_title = exclusion.normalized_title;

COMMIT;

SELECT classification_status, count(*) AS titles
FROM jobpush.job_title_labels
WHERE lower(normalized_title) ~ '(^|[^a-z])(project manager|program manager|project management|program management)([^a-z]|$)'
GROUP BY 1;
