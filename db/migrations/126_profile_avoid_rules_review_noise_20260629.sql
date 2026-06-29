BEGIN;

-- High-volume review noise seen after the 2026-06-29 local-title-ml-v4 pass.
-- ponytail: narrow phrases only; broad "coordinator/support/manager" rules
-- would collide with known target titles.

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-06-29-review-noise','non_target',NULL,'learning development trainer','(^|[^a-z])(learning development trainer|core trainer|technical trainer|trainer)([^a-z]|$)','title_review_noise_audit_2026-06-29','profile_avoid_training_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-29-review-noise','non_target',NULL,'admin staffing coordinator','(^|[^a-z])(admin coordinator|administrative coordinator|staffing administrator|personnel coordinator|candidate attraction|workforce staffing)([^a-z]|$)','title_review_noise_audit_2026-06-29','profile_avoid_admin_staffing_coordination',18,TRUE),
    ('profile-title-rules-v2','2026-06-29-review-noise','non_target',NULL,'merchandise retail ops','(^|[^a-z])(merchandise execution|home shopping manager|drive up go supervisor|person in charge|pic|athlete ii)([^a-z]|$)','title_review_noise_audit_2026-06-29','profile_avoid_retail_operations_titles',18,TRUE),
    ('profile-title-rules-v2','2026-06-29-review-noise','non_target',NULL,'procurement inspection facilities','(^|[^a-z])(site procurement manager|procurement representative|sprinkler inspector|operating engineer-licensed|landscape foreman|stormwater)([^a-z]|$)','title_review_noise_audit_2026-06-29','profile_avoid_procurement_facilities_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-29-review-noise','non_target',NULL,'territory medical sales','(^|[^a-z])(territory associate|territory account manager|inside territory account manager|diagnostics sales developer|cardiovascular sales manager|cardiovascular program specialist)([^a-z]|$)','title_review_noise_audit_2026-06-29','profile_avoid_territory_medical_sales',18,TRUE),
    ('profile-title-rules-v2','2026-06-29-review-noise','non_target',NULL,'clinical technologist','(^|[^a-z])(radiologic technologist|ultrasound technologist|medical technologist|histotechnologist|phlebotomy|dialysis technician)([^a-z]|$)','title_review_noise_audit_2026-06-29','profile_avoid_clinical_technologist_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-29-review-noise','non_target',NULL,'prime air frontline','(^|[^a-z])(flight monitor|prime air flight monitor|prime air ground handler|ground handler)([^a-z]|$)','title_review_noise_audit_2026-06-29','profile_avoid_prime_air_frontline_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-29-review-noise','non_target',NULL,'hospitality banquet','(^|[^a-z])(banquet manager|room operations)([^a-z]|$)','title_review_noise_audit_2026-06-29','profile_avoid_hospitality_operations_roles',18,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE title_review_noise_updates_20260629 ON COMMIT DROP AS
WITH exact_updates(normalized_title, decision_reason) AS (
    VALUES
        ('associate learning development trainer associate learning development', 'profile_avoid_training_roles'),
        ('associate learning development trainer', 'profile_avoid_training_roles'),
        ('core trainer china grove - full time', 'profile_avoid_training_roles'),
        ('technical trainer', 'profile_avoid_training_roles'),
        ('admin coordinator', 'profile_avoid_admin_staffing_coordination'),
        ('in-market administrator candidate attraction', 'profile_avoid_admin_staffing_coordination'),
        ('reduced time rt staffing administrator workforce staffing', 'profile_avoid_admin_staffing_coordination'),
        ('personnel coordinator', 'profile_avoid_admin_staffing_coordination'),
        ('manager merchandise execution', 'profile_avoid_retail_operations_titles'),
        ('assistant drive up go supervisor', 'profile_avoid_retail_operations_titles'),
        ('assistant home shopping manager', 'profile_avoid_retail_operations_titles'),
        ('home shopping manager', 'profile_avoid_retail_operations_titles'),
        ('person in charge pic', 'profile_avoid_retail_operations_titles'),
        ('athlete ii', 'profile_avoid_retail_operations_titles'),
        ('site procurement manager', 'profile_avoid_procurement_facilities_roles'),
        ('procurement representative', 'profile_avoid_procurement_facilities_roles'),
        ('sprinkler inspector', 'profile_avoid_procurement_facilities_roles'),
        ('operating engineer-licensed', 'profile_avoid_procurement_facilities_roles'),
        ('landscape foreman stormwater', 'profile_avoid_procurement_facilities_roles'),
        ('inside territory account manager', 'profile_avoid_territory_medical_sales'),
        ('territory account manager', 'profile_avoid_territory_medical_sales'),
        ('diagnostics sales developer', 'profile_avoid_territory_medical_sales'),
        ('da vinci cardiovascular sales manager', 'profile_avoid_territory_medical_sales'),
        ('cardiovascular program specialist', 'profile_avoid_territory_medical_sales'),
        ('endoluminal territory associate', 'profile_avoid_territory_medical_sales'),
        ('endoluminal territory associate - future opportunity', 'profile_avoid_territory_medical_sales'),
        ('radiologic technologist', 'profile_avoid_clinical_technologist_roles'),
        ('ultrasound technologist', 'profile_avoid_clinical_technologist_roles'),
        ('medical technologist', 'profile_avoid_clinical_technologist_roles'),
        ('histotechnologist', 'profile_avoid_clinical_technologist_roles'),
        ('phlebotomy site coordinator', 'profile_avoid_clinical_technologist_roles'),
        ('dialysis technician', 'profile_avoid_clinical_technologist_roles'),
        ('flight monitor amazon - prime air', 'profile_avoid_prime_air_frontline_roles'),
        ('prime air flight monitor amazon prime air', 'profile_avoid_prime_air_frontline_roles'),
        ('prime air ground handler corporate operations', 'profile_avoid_prime_air_frontline_roles'),
        ('banquet manager', 'profile_avoid_hospitality_operations_roles'),
        ('assistant manager - room operations', 'profile_avoid_hospitality_operations_roles')
)
SELECT
    label.normalized_title,
    label.classification_status AS previous_status,
    'non_target'::text AS new_status,
    NULL::text AS canonical_role,
    exact_updates.decision_reason
FROM exact_updates
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE label.classification_status = 'review'
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT update_plan.normalized_title, update_plan.previous_status, update_plan.new_status, update_plan.canonical_role,
       update_plan.decision_reason || ': candidate_profile 2026-06-29',
       'system:profile-title-rules-v2'
FROM title_review_noise_updates_20260629 update_plan
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE label.classification_status IS DISTINCT FROM update_plan.new_status
   OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
   OR label.canonical_role IS DISTINCT FROM update_plan.canonical_role
   OR label.decision_reason IS DISTINCT FROM update_plan.decision_reason || ': candidate_profile 2026-06-29';

UPDATE jobpush.job_title_labels label
SET classification_status = update_plan.new_status,
    canonical_role = update_plan.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = update_plan.decision_reason || ': candidate_profile 2026-06-29',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM title_review_noise_updates_20260629 update_plan
WHERE label.normalized_title = update_plan.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM title_review_noise_updates_20260629 update_plan
WHERE ml.normalized_title = update_plan.normalized_title;

COMMIT;

SELECT classification_status, rule_version, decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_%: candidate_profile 2026-06-29'
GROUP BY 1, 2, 3
ORDER BY titles DESC;
