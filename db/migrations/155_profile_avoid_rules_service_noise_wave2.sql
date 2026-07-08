BEGIN;

-- ponytail: second narrow cleanup from the current review queue audit.
-- These are frontline/service/clinical titles, not ambiguous tech roles.
INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-07-draft-16','non_target',NULL,'security valet monitor frontline roles','(^|[^a-z])(security officer|security officers|security guard|valet|valet attendant|bus monitor|aide monitor|monitor aide|direct support professional)([^a-z]|$)','title_review_noise_audit_2026-07-07','profile_avoid_security_valet_monitor_frontline_roles',18,TRUE),
    ('profile-title-rules-v2','2026-07-07-draft-16','non_target',NULL,'care resident chaplain medical records roles','(^|[^a-z])(care worker|caregiver|chaplain|resident -?pgy|medical records specialist|roi medical records specialist)([^a-z]|$)','title_review_noise_audit_2026-07-07','profile_avoid_care_resident_medical_records_roles',18,TRUE),
    ('profile-title-rules-v2','2026-07-07-draft-16','non_target',NULL,'data entry office operator roles','(^|[^a-z])(data entry operator|data entry clerk|office clerk|general offices|front office associate|office assistant)([^a-z]|$)','title_review_noise_audit_2026-07-07','profile_avoid_data_entry_office_operator_roles',18,TRUE),
    ('profile-title-rules-v2','2026-07-07-draft-16','non_target',NULL,'carrier logistics frontline roles','(^|[^a-z])(carrier|courier|delivery|package handler|route driver|cdl driver|truck driver|forklift operator)([^a-z]|$)','title_review_noise_audit_2026-07-07','profile_avoid_carrier_logistics_frontline_roles',18,TRUE),
    ('profile-title-rules-v2','2026-07-07-draft-16','non_target',NULL,'corrugate factory technician roles','(^|[^a-z])(corrugate tech|corrugator|press operator|machine operator|plant technician)([^a-z]|$)','title_review_noise_audit_2026-07-07','profile_avoid_factory_operator_technician_roles',18,TRUE)
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
       CASE
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(security officer|security officers|security guard|valet|valet attendant|bus monitor|aide monitor|monitor aide|direct support professional)([^a-z]|$)'
               THEN 'profile_avoid_security_valet_monitor_frontline_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(care worker|caregiver|chaplain|resident -?pgy|medical records specialist|roi medical records specialist)([^a-z]|$)'
               THEN 'profile_avoid_care_resident_medical_records_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(data entry operator|data entry clerk|office clerk|general offices|front office associate|office assistant)([^a-z]|$)'
               THEN 'profile_avoid_data_entry_office_operator_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(carrier|courier|delivery|package handler|route driver|cdl driver|truck driver|forklift operator)([^a-z]|$)'
               THEN 'profile_avoid_carrier_logistics_frontline_roles'
           ELSE 'profile_avoid_factory_operator_technician_roles'
       END AS decision_reason
FROM jobpush.job_title_labels label
WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
  AND (
      lower(label.normalized_title) ~ '(^|[^a-z])(security officer|security officers|security guard|valet|valet attendant|bus monitor|aide monitor|monitor aide|direct support professional)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(care worker|caregiver|chaplain|resident -?pgy|medical records specialist|roi medical records specialist)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(data entry operator|data entry clerk|office clerk|general offices|front office associate|office assistant)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(carrier|courier|delivery|package handler|route driver|cdl driver|truck driver|forklift operator)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(corrugate tech|corrugator|press operator|machine operator|plant technician)([^a-z]|$)'
  );

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT update_plan.normalized_title, update_plan.previous_status, update_plan.new_status, update_plan.canonical_role,
       update_plan.decision_reason || ': candidate_profile 2026-07-07',
       'system:profile-title-rules-v2'
FROM title_noise_updates update_plan
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE label.classification_status IS DISTINCT FROM update_plan.new_status
   OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
   OR label.canonical_role IS DISTINCT FROM update_plan.canonical_role
   OR label.decision_reason IS DISTINCT FROM update_plan.decision_reason || ': candidate_profile 2026-07-07';

UPDATE jobpush.job_title_labels label
SET classification_status = update_plan.new_status,
    canonical_role = update_plan.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = update_plan.decision_reason || ': candidate_profile 2026-07-07',
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
WHERE decision_reason LIKE 'profile_avoid_security_valet_monitor_frontline_roles%%'
   OR decision_reason LIKE 'profile_avoid_care_resident_medical_records_roles%%'
   OR decision_reason LIKE 'profile_avoid_data_entry_office_operator_roles%%'
   OR decision_reason LIKE 'profile_avoid_carrier_logistics_frontline_roles%%'
   OR decision_reason LIKE 'profile_avoid_factory_operator_technician_roles%%'
GROUP BY decision_reason
ORDER BY titles DESC;
