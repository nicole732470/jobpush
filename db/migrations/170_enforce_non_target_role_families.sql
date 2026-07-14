\set ON_ERROR_STOP on
\pset pager off

BEGIN;

CREATE TEMP TABLE role_family_non_targets ON COMMIT DROP AS
SELECT DISTINCT fast.normalized_title, label.classification_status AS previous_status
FROM jobpush.dashboard_jobs_fast fast
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE role_family IN ('software_engineering', 'program_manager', 'project_manager');

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, 'non_target', NULL,
       'explicit_non_target_role_family', 'nicole'
FROM role_family_non_targets
WHERE previous_status IS DISTINCT FROM 'non_target';

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'manual-profile-role-family-v1',
    decision_reason = 'explicit_non_target_role_family',
    labeled_by = 'nicole',
    labeled_at = NOW(),
    updated_at = NOW()
FROM role_family_non_targets excluded
WHERE label.normalized_title = excluded.normalized_title;

UPDATE jobpush.job_title_ml_classifications prediction
SET applied = FALSE
FROM role_family_non_targets excluded
WHERE prediction.normalized_title = excluded.normalized_title
  AND prediction.applied;

SELECT classification_status, count(DISTINCT label.normalized_title) AS titles
FROM jobpush.job_title_labels label
JOIN role_family_non_targets excluded USING (normalized_title)
GROUP BY 1;

COMMIT;
