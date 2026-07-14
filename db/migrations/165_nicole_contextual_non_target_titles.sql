\pset pager off

BEGIN;

-- Contextual phrase rules from Nicole's 2026-07-13 review. These intentionally
-- require role-level phrases; no single generic word is a decision boundary.
INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-13-draft-20','non_target',NULL,'project and program manager roles','(^|[^a-z])(project manager|program manager)([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_project_program_manager_roles',8,TRUE),
    ('profile-title-rules-v2','2026-07-13-draft-20','non_target',NULL,'security role phrases','(^|[^a-z])(security engineer|security analyst|security architect|security manager|security specialist|security consultant|security administrator|security operations (engineer|analyst|manager|specialist)|information systems security manager|devsecops engineer)([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_security_roles',8,TRUE),
    ('profile-title-rules-v2','2026-07-13-draft-20','non_target',NULL,'quantitative role phrases','(^|[^a-z])(quantitative (developer|analyst|researcher|engineer|trader)|quant (developer|analyst|researcher|engineer|trader))([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_quantitative_roles',8,TRUE),
    ('profile-title-rules-v2','2026-07-13-draft-20','non_target',NULL,'technical operations role phrases','(^|[^a-z])(application support (engineer|analyst)|production support (engineer|analyst)|site reliability engineer|systems? administrator|network administrator|devops engineer|devsecops engineer|infrastructure engineer|cloud operations (engineer|analyst|manager|specialist)|it operations (engineer|analyst|manager|specialist)|technical operations (engineer|analyst|manager|specialist)|ai infrastructure engineer)([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_technical_operations_roles',8,TRUE),
    ('profile-title-rules-v2','2026-07-13-draft-20','non_target',NULL,'software testing role phrases','(^|[^a-z])(qa engineer|qa analyst|quality assurance engineer|quality assurance analyst|software test engineer|test automation engineer|automation test engineer|test engineer|test analyst|testing engineer|software tester|sdet)([^a-z]|$)','nicole_review_2026-07-13','profile_avoid_software_testing_roles',8,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE nicole_exact_labels (
    normalized_title TEXT PRIMARY KEY
) ON COMMIT DROP;

INSERT INTO nicole_exact_labels VALUES
    ('healthcare assistant'),
    ('devsecops engineer'),
    ('information systems security manager issm'),
    ('operations research analyst cyber/intelligence'),
    ('software integration engineer'),
    ('application support engineer'),
    ('engineering program manager'),
    ('ai infrastructure engineer iv'),
    ('cloud security architect'),
    ('quantitative developer');

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT label.normalized_title, label.classification_status, 'non_target', NULL,
       'nicole_contextual_title_review_2026-07-13', 'nicole'
FROM jobpush.job_title_labels label
JOIN nicole_exact_labels exact USING (normalized_title)
WHERE label.classification_status IS DISTINCT FROM 'non_target'
   OR label.rule_version IS DISTINCT FROM 'manual-nicole-contextual-2026-07-13';

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'manual-nicole-contextual-2026-07-13',
    decision_reason = 'nicole_contextual_title_review_2026-07-13',
    labeled_by = 'nicole',
    labeled_at = now(),
    updated_at = now()
FROM nicole_exact_labels exact
WHERE label.normalized_title = exact.normalized_title;

CREATE TEMP TABLE contextual_rule_updates ON COMMIT DROP AS
SELECT label.normalized_title,
       label.classification_status AS previous_status,
       CASE
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(project manager|program manager)([^a-z]|$)'
               THEN 'profile_avoid_project_program_manager_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(security engineer|security analyst|security architect|security manager|security specialist|security consultant|security administrator|security operations (engineer|analyst|manager|specialist)|information systems security manager|devsecops engineer)([^a-z]|$)'
               THEN 'profile_avoid_security_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(quantitative (developer|analyst|researcher|engineer|trader)|quant (developer|analyst|researcher|engineer|trader))([^a-z]|$)'
               THEN 'profile_avoid_quantitative_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(application support (engineer|analyst)|production support (engineer|analyst)|site reliability engineer|systems? administrator|network administrator|devops engineer|devsecops engineer|infrastructure engineer|cloud operations (engineer|analyst|manager|specialist)|it operations (engineer|analyst|manager|specialist)|technical operations (engineer|analyst|manager|specialist)|ai infrastructure engineer)([^a-z]|$)'
               THEN 'profile_avoid_technical_operations_roles'
           ELSE 'profile_avoid_software_testing_roles'
       END AS decision_reason
FROM jobpush.job_title_labels label
WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
  AND (
      lower(label.normalized_title) ~ '(^|[^a-z])(project manager|program manager)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(security engineer|security analyst|security architect|security manager|security specialist|security consultant|security administrator|security operations (engineer|analyst|manager|specialist)|information systems security manager|devsecops engineer)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(quantitative (developer|analyst|researcher|engineer|trader)|quant (developer|analyst|researcher|engineer|trader))([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(application support (engineer|analyst)|production support (engineer|analyst)|site reliability engineer|systems? administrator|network administrator|devops engineer|devsecops engineer|infrastructure engineer|cloud operations (engineer|analyst|manager|specialist)|it operations (engineer|analyst|manager|specialist)|technical operations (engineer|analyst|manager|specialist)|ai infrastructure engineer)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(qa engineer|qa analyst|quality assurance engineer|quality assurance analyst|software test engineer|test automation engineer|automation test engineer|test engineer|test analyst|testing engineer|software tester|sdet)([^a-z]|$)'
  );

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, 'non_target', NULL,
       decision_reason || ': candidate_profile 2026-07-13',
       'system:profile-title-rules-v2'
FROM contextual_rule_updates
WHERE previous_status IS DISTINCT FROM 'non_target';

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'profile-title-rules-v2',
    decision_reason = updates.decision_reason || ': candidate_profile 2026-07-13',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM contextual_rule_updates updates
WHERE label.normalized_title = updates.normalized_title;

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
WHERE EXISTS (
    SELECT 1 FROM nicole_exact_labels exact
    WHERE exact.normalized_title = ml.normalized_title
)
OR EXISTS (
    SELECT 1 FROM contextual_rule_updates updates
    WHERE updates.normalized_title = ml.normalized_title
);

COMMIT;

SELECT decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE '%2026-07-13%'
GROUP BY 1
ORDER BY titles DESC;
