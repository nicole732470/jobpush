\pset pager off

BEGIN;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-13-draft-21','non_target',NULL,'mobile software engineering roles','(^|[^a-z])((ios|android|mobile)( software)? (engineer|developer))([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_mobile_sde_roles',7,TRUE),
    ('profile-title-rules-v2','2026-07-13-draft-21','non_target',NULL,'administrative assistant roles','(^|[^a-z])(administrative assistant|admin assistant)([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_administrative_assistant_roles',7,TRUE),
    ('profile-title-rules-v2','2026-07-13-draft-21','non_target',NULL,'project management roles','(^|[^a-z])(project management)([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_project_management_roles',7,TRUE),
    ('profile-title-rules-v2','2026-07-13-draft-21','non_target',NULL,'it operations management roles','(^|[^a-z])((it|information technology) operations (management|manager|engineer|analyst|specialist))([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_it_operations_management_roles',7,TRUE),
    ('profile-title-rules-v2','2026-07-13-draft-21','non_target',NULL,'cyber security roles','(^|[^a-z])(cyber[ -]?security (engineer|analyst|architect|manager|specialist|consultant|administrator))([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_cyber_security_roles',7,TRUE),
    ('profile-title-rules-v2','2026-07-13-draft-21','non_target',NULL,'generic engineer title','^engineer$','nicole_review_2026-07-13','profile_avoid_generic_engineer_title',7,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE jobs_to_apply_leak_updates ON COMMIT DROP AS
SELECT label.normalized_title,
       label.classification_status AS previous_status,
       CASE
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])((ios|android|mobile)( software)? (engineer|developer))([^a-z]|$)'
               THEN 'profile_avoid_mobile_sde_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(administrative assistant|admin assistant)([^a-z]|$)'
               THEN 'profile_avoid_administrative_assistant_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(project management)([^a-z]|$)'
               THEN 'profile_avoid_project_management_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])((it|information technology) operations (management|manager|engineer|analyst|specialist))([^a-z]|$)'
               THEN 'profile_avoid_it_operations_management_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(cyber[ -]?security (engineer|analyst|architect|manager|specialist|consultant|administrator))([^a-z]|$)'
               THEN 'profile_avoid_cyber_security_roles'
           ELSE 'profile_avoid_generic_engineer_title'
       END AS decision_reason
FROM jobpush.job_title_labels label
WHERE lower(label.normalized_title) ~ '(^engineer$|(^|[^a-z])((ios|android|mobile)( software)? (engineer|developer)|administrative assistant|admin assistant|project management|(it|information technology) operations (management|manager|engineer|analyst|specialist)|cyber[ -]?security (engineer|analyst|architect|manager|specialist|consultant|administrator))([^a-z]|$))';

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, 'non_target', NULL,
       decision_reason || ': candidate_profile 2026-07-13', 'nicole'
FROM jobs_to_apply_leak_updates
WHERE previous_status IS DISTINCT FROM 'non_target';

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'profile-title-rules-v2',
    decision_reason = updates.decision_reason || ': candidate_profile 2026-07-13',
    labeled_by = 'nicole',
    labeled_at = now(),
    updated_at = now()
FROM jobs_to_apply_leak_updates updates
WHERE label.normalized_title = updates.normalized_title;

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM jobs_to_apply_leak_updates updates
WHERE ml.normalized_title = updates.normalized_title;

COMMIT;

SELECT decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_%candidate_profile 2026-07-13'
GROUP BY 1
ORDER BY titles DESC;
