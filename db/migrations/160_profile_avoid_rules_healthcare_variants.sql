BEGIN;

-- ponytail: patch healthcare/pharma variants that leaked through review after v5.
INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-08-draft-18','non_target',NULL,'healthcare pharma variant roles','(^|[^a-z])(preclinical|pharmacovigilance|pharmacology|biopharma|pharmaceuticals?|radiologist|neuroradiologist|physicians?|neurohospitalist|hospitals?|anti-infectives?|nurses?|nursery|rns|licensed practical nurses?)([^a-z]|$)','title_review_noise_audit_2026-07-08','profile_avoid_healthcare_pharma_variant_roles',21,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE title_noise_updates ON COMMIT DROP AS
SELECT label.normalized_title,
       label.classification_status AS previous_status,
       'non_target'::text AS new_status,
       NULL::text AS canonical_role,
       'profile_avoid_healthcare_pharma_variant_roles'::text AS decision_reason
FROM jobpush.job_title_labels label
WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
  AND lower(label.normalized_title) ~ '(^|[^a-z])(preclinical|pharmacovigilance|pharmacology|biopharma|pharmaceuticals?|radiologist|neuroradiologist|physicians?|neurohospitalist|hospitals?|anti-infectives?|nurses?|nursery|rns|licensed practical nurses?)([^a-z]|$)';

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT update_plan.normalized_title, update_plan.previous_status, update_plan.new_status, update_plan.canonical_role,
       update_plan.decision_reason || ': candidate_profile 2026-07-08',
       'system:profile-title-rules-v2'
FROM title_noise_updates update_plan
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE label.classification_status IS DISTINCT FROM update_plan.new_status
   OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
   OR label.canonical_role IS DISTINCT FROM update_plan.canonical_role
   OR label.decision_reason IS DISTINCT FROM update_plan.decision_reason || ': candidate_profile 2026-07-08';

UPDATE jobpush.job_title_labels label
SET classification_status = update_plan.new_status,
    canonical_role = update_plan.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = update_plan.decision_reason || ': candidate_profile 2026-07-08',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM title_noise_updates update_plan
WHERE label.normalized_title = update_plan.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM title_noise_updates update_plan
WHERE ml.normalized_title = update_plan.normalized_title;

COMMIT;

SELECT decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_healthcare_pharma_variant_roles%%'
GROUP BY decision_reason;
