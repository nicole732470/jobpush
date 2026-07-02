BEGIN;

-- Nicole no longer wants pure SDE/software-implementation roles in the
-- application target queue. Keep data/BI/product/solutions tracks intact.
INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES (
    'profile-title-rules-v2',
    '2026-07-01-draft-10',
    'non_target',
    NULL,
    'pure sde software engineering',
    '(^|[^a-z0-9])(sde|software engineer|software developer|software engineering|full[- ]stack|fullstack|backend|back[- ]end|front[- ]end|frontend|devops|qa engineer|quality assurance engineer|test engineer|tester|sdet)([^a-z0-9]|$)',
    'nicole_hard_exclusion_2026-07-01',
    'profile_avoid_pure_sde_software_engineering_roles',
    16,
    TRUE
)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE pure_sde_title_updates_20260701 ON COMMIT DROP AS
SELECT label.normalized_title,
       label.classification_status AS previous_status,
       'non_target'::text AS new_status,
       NULL::text AS canonical_role,
       'profile_avoid_pure_sde_software_engineering_roles'::text AS decision_reason
FROM jobpush.job_title_labels label
WHERE lower(label.normalized_title) ~ '(^|[^a-z0-9])(sde|software engineer|software developer|software engineering|full[- ]stack|fullstack|backend|back[- ]end|front[- ]end|frontend|devops|qa engineer|quality assurance engineer|test engineer|tester|sdet)([^a-z0-9]|$)'
  AND (label.classification_status IS DISTINCT FROM 'non_target'
       OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
       OR label.canonical_role IS NOT NULL
       OR label.decision_reason IS DISTINCT FROM 'profile_avoid_pure_sde_software_engineering_roles: candidate_profile 2026-07-01');

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-07-01',
       'system:profile-title-rules-v2'
FROM pure_sde_title_updates_20260701;

UPDATE jobpush.job_title_labels label
SET classification_status = update_plan.new_status,
    canonical_role = update_plan.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = update_plan.decision_reason || ': candidate_profile 2026-07-01',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM pure_sde_title_updates_20260701 update_plan
WHERE label.normalized_title = update_plan.normalized_title;

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM pure_sde_title_updates_20260701 update_plan
WHERE ml.normalized_title = update_plan.normalized_title;

COMMIT;

SELECT count(*) AS pure_sde_titles_now_non_target
FROM jobpush.job_title_labels
WHERE decision_reason = 'profile_avoid_pure_sde_software_engineering_roles: candidate_profile 2026-07-01';

SELECT count(*) AS open_target_jobs
FROM jobpush.dashboard_jobs
WHERE role_status = 'target'
  AND application_status IN ('new','saved','apply_next','referred');
