\pset pager off

BEGIN;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-14-draft-10','non_target',NULL,
     'java developer roles','(^|[^a-z])java developer(s)?([^a-z]|$)',
     'candidate_profile.avoid_tracks.pure_sde','profile_avoid_java_developer_roles',7,TRUE),
    ('profile-title-rules-v2','2026-07-14-draft-10','non_target',NULL,
     'material handler roles','(^|[^a-z])material handler(s)?([^a-z]|$)',
     'candidate_profile.avoid_tracks.frontline_service_facilities_and_trades','profile_avoid_material_handler_roles',7,TRUE),
    ('profile-title-rules-v2','2026-07-14-draft-10','non_target',NULL,
     'sales coordinator roles','(^|[^a-z])sales coordinator(s)?([^a-z]|$)',
     'candidate_profile.avoid_tracks.pure_sales','profile_avoid_sales_coordinator_roles',7,TRUE),
    ('profile-title-rules-v2','2026-07-14-draft-10','non_target',NULL,
     'customer service specialist roles','(^|[^a-z])customer service specialist(s)?([^a-z]|$)',
     'candidate_profile.avoid_tracks.frontline_service_facilities_and_trades','profile_avoid_customer_service_specialist_roles',7,TRUE)
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
           WHEN lower(normalized_title) ~ '(^|[^a-z])java developer(s)?([^a-z]|$)'
               THEN 'profile_avoid_java_developer_roles'
           WHEN lower(normalized_title) ~ '(^|[^a-z])material handler(s)?([^a-z]|$)'
               THEN 'profile_avoid_material_handler_roles'
           WHEN lower(normalized_title) ~ '(^|[^a-z])sales coordinator(s)?([^a-z]|$)'
               THEN 'profile_avoid_sales_coordinator_roles'
           ELSE 'profile_avoid_customer_service_specialist_roles'
       END AS decision_reason
FROM jobpush.job_title_labels
WHERE lower(normalized_title) ~ '(^|[^a-z])(java developer(s)?|material handler(s)?|sales coordinator(s)?|customer service specialist(s)?)([^a-z]|$)';

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, 'non_target', NULL,
       decision_reason || ': candidate_profile 2026-07-14-draft-10', 'nicole'
FROM corrected_titles
WHERE previous_status IS DISTINCT FROM 'non_target';

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'manual-profile-2026-07-14',
    decision_reason = correction.decision_reason || ': candidate_profile 2026-07-14-draft-10',
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
WHERE decision_reason LIKE 'profile_avoid_%: candidate_profile 2026-07-14-draft-10'
GROUP BY 1
ORDER BY 1;

SELECT role_status, count(*) AS active_jobs
FROM jobpush.dashboard_jobs_fast
WHERE normalized_title ~* '(^|[^a-z])(java developer(s)?|material handler(s)?|sales coordinator(s)?|customer service specialist(s)?)([^a-z]|$)'
GROUP BY 1
ORDER BY 1;
