\pset pager off

BEGIN;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-14-draft-9','non_target',NULL,
     'account executive roles','(^|[^a-z])account executive(s)?([^a-z]|$)',
     'candidate_profile.avoid_tracks.pure_sales','profile_avoid_account_executive_roles',7,TRUE),
    ('profile-title-rules-v2','2026-07-14-draft-9','non_target',NULL,
     'administrative business partner roles','(^|[^a-z])administrative business partner(s)?([^a-z]|$)',
     'candidate_profile.avoid_tracks.administrative_support','profile_avoid_administrative_business_partner_roles',7,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE corrected_titles ON COMMIT DROP AS
SELECT normalized_title,
       classification_status AS previous_status,
       CASE
           WHEN lower(normalized_title) ~ '(^|[^a-z])account executive(s)?([^a-z]|$)'
               THEN 'profile_avoid_account_executive_roles'
           ELSE 'profile_avoid_administrative_business_partner_roles'
       END AS decision_reason
FROM jobpush.job_title_labels
WHERE lower(normalized_title) ~ '(^|[^a-z])(account executive(s)?|administrative business partner(s)?)([^a-z]|$)';

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, 'non_target', NULL,
       decision_reason || ': candidate_profile 2026-07-14-draft-9', 'nicole'
FROM corrected_titles
WHERE previous_status IS DISTINCT FROM 'non_target';

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'manual-profile-2026-07-14',
    decision_reason = correction.decision_reason || ': candidate_profile 2026-07-14-draft-9',
    labeled_by = 'nicole',
    labeled_at = now(),
    updated_at = now()
FROM corrected_titles correction
WHERE label.normalized_title = correction.normalized_title;

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM corrected_titles correction
WHERE ml.normalized_title = correction.normalized_title
  AND ml.applied;

UPDATE jobpush.dashboard_jobs_fast fast
SET role_status = 'non_target',
    canonical_role = NULL
FROM corrected_titles correction
WHERE fast.normalized_title = correction.normalized_title
  AND (fast.role_status IS DISTINCT FROM 'non_target' OR fast.canonical_role IS NOT NULL);

COMMIT;

SELECT decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason IN (
    'profile_avoid_account_executive_roles: candidate_profile 2026-07-14-draft-9',
    'profile_avoid_administrative_business_partner_roles: candidate_profile 2026-07-14-draft-9'
)
GROUP BY 1
ORDER BY 1;

SELECT role_status, count(*) AS active_jobs
FROM jobpush.dashboard_jobs_fast
WHERE normalized_title ~* '(^|[^a-z])(account executive(s)?|administrative business partner(s)?)([^a-z]|$)'
GROUP BY 1
ORDER BY 1;
