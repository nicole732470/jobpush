BEGIN;

-- ponytail: narrow hard-avoid terms from Nicole's latest title review.
-- Avoid broad "service/services" because it collides with technical services roles.
INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-07-draft-15','non_target',NULL,'dental clinical service roles','(^|[^a-z])(dentist|dental hygienist|dental assistant|orthodontic assistant|oral surgeon|endodontist|periodontist)([^a-z]|$)','nicole_title_review_2026-07-07','profile_avoid_dental_clinical_roles',18,TRUE),
    ('profile-title-rules-v2','2026-07-07-draft-15','non_target',NULL,'cafe restaurant food service roles','(^|[^a-z])(barista|cafe|café|server|restaurant|cook|line cook|prep cook|hostess|host|busser|dishwasher|food runner|kitchen manager|shift leader)([^a-z]|$)','nicole_title_review_2026-07-07','profile_avoid_cafe_restaurant_food_service_roles',18,TRUE),
    ('profile-title-rules-v2','2026-07-07-draft-15','non_target',NULL,'shopping retail frontline roles','(^|[^a-z])(personal shopper|shopper|cashier|sales floor|store associate|retail associate|shopping|cart attendant|stocker|stocker receiver|merchandise associate)([^a-z]|$)','nicole_title_review_2026-07-07','profile_avoid_shopping_retail_frontline_roles',18,TRUE),
    ('profile-title-rules-v2','2026-07-07-draft-15','non_target',NULL,'courier carrier delivery frontline roles','(^|[^a-z])(courier|mail carrier|letter carrier|city carrier|delivery driver|route driver|package handler|package delivery|loader unloader)([^a-z]|$)','nicole_title_review_2026-07-07','profile_avoid_courier_delivery_frontline_roles',18,TRUE)
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
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(dentist|dental hygienist|dental assistant|orthodontic assistant|oral surgeon|endodontist|periodontist)([^a-z]|$)'
               THEN 'profile_avoid_dental_clinical_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(barista|cafe|café|server|restaurant|cook|line cook|prep cook|hostess|host|busser|dishwasher|food runner|kitchen manager|shift leader)([^a-z]|$)'
               THEN 'profile_avoid_cafe_restaurant_food_service_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(personal shopper|shopper|cashier|sales floor|store associate|retail associate|shopping|cart attendant|stocker|stocker receiver|merchandise associate)([^a-z]|$)'
               THEN 'profile_avoid_shopping_retail_frontline_roles'
           ELSE 'profile_avoid_courier_delivery_frontline_roles'
       END AS decision_reason
    FROM jobpush.job_title_labels label
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND (
          lower(label.normalized_title) ~ '(^|[^a-z])(dentist|dental hygienist|dental assistant|orthodontic assistant|oral surgeon|endodontist|periodontist)([^a-z]|$)'
          OR lower(label.normalized_title) ~ '(^|[^a-z])(barista|cafe|café|server|restaurant|cook|line cook|prep cook|hostess|host|busser|dishwasher|food runner|kitchen manager|shift leader)([^a-z]|$)'
          OR lower(label.normalized_title) ~ '(^|[^a-z])(personal shopper|shopper|cashier|sales floor|store associate|retail associate|shopping|cart attendant|stocker|stocker receiver|merchandise associate)([^a-z]|$)'
          OR lower(label.normalized_title) ~ '(^|[^a-z])(courier|mail carrier|letter carrier|city carrier|delivery driver|route driver|package handler|package delivery|loader unloader)([^a-z]|$)'
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
WHERE decision_reason LIKE 'profile_avoid_dental_clinical_roles%%'
   OR decision_reason LIKE 'profile_avoid_cafe_restaurant_food_service_roles%%'
   OR decision_reason LIKE 'profile_avoid_shopping_retail_frontline_roles%%'
   OR decision_reason LIKE 'profile_avoid_courier_delivery_frontline_roles%%'
GROUP BY decision_reason
ORDER BY titles DESC;
