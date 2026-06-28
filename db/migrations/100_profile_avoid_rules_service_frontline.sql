BEGIN;

-- Nicole title-review issue, 2026-06-28:
-- Driver, front-desk, hospitality, security, healthcare support, and trade
-- roles are frontline/service jobs, not JobPush recommendation candidates.

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-11',
        'non_target',
        NULL,
        'driver courier delivery',
        '(^|[^a-z])(driver|delivery driver|truck driver|route driver|bus driver|van driver|driver helper|courier|chauffeur)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_service_noise',
        'profile_avoid_driver_delivery_roles',
        18,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-11',
        'non_target',
        NULL,
        'front desk receptionist hospitality',
        '(^|[^a-z])(front desk|receptionist|concierge|guest service|guest services|hotel|hospitality|host|hostess)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_service_noise',
        'profile_avoid_front_desk_hospitality_roles',
        18,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-11',
        'non_target',
        NULL,
        'restaurant food service',
        '(^|[^a-z])(restaurant|food service|foodservice|server|bartender|barista|cook|chef|kitchen|dishwasher|crew member|grill)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_service_noise',
        'profile_avoid_restaurant_food_service_roles',
        18,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-11',
        'non_target',
        NULL,
        'security guard officer',
        '(^|[^a-z])(security guard|security officer|loss prevention|asset protection associate|patrol officer)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_service_noise',
        'profile_avoid_security_guard_roles',
        18,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-11',
        'non_target',
        NULL,
        'healthcare support nursing therapy',
        '(^|[^a-z])(nurse|nursing|physician|doctor|medical assistant|pharmacy technician|dental|therapist|therapy|psychiatrist|caregiver|patient care|veterinary|veterinarian)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_service_noise',
        'profile_avoid_healthcare_support_roles',
        18,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-11',
        'non_target',
        NULL,
        'manual trade technician',
        '(^|[^a-z])(plumber|plumbing|electrician|hvac|mechanic|maintenance tech|maintenance technician|field technician|service technician|installer|repair technician)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_service_noise',
        'profile_avoid_manual_trade_roles',
        18,
        TRUE
    )
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE service_frontline_title_updates ON COMMIT DROP AS
WITH candidates AS (
    SELECT
        label.normalized_title,
        label.classification_status AS previous_status,
        lower(label.normalized_title) AS title
    FROM jobpush.job_title_labels label
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND (
          label.normalized_title ILIKE '%driver%'
          OR label.normalized_title ILIKE '%courier%'
          OR label.normalized_title ILIKE '%chauffeur%'
          OR label.normalized_title ILIKE '%front desk%'
          OR label.normalized_title ILIKE '%reception%'
          OR label.normalized_title ILIKE '%concierge%'
          OR label.normalized_title ILIKE '%guest service%'
          OR label.normalized_title ILIKE '%hotel%'
          OR label.normalized_title ILIKE '%hospitality%'
          OR label.normalized_title ILIKE '%host%'
          OR label.normalized_title ILIKE '%restaurant%'
          OR label.normalized_title ILIKE '%food%'
          OR label.normalized_title ILIKE '%server%'
          OR label.normalized_title ILIKE '%bartender%'
          OR label.normalized_title ILIKE '%barista%'
          OR label.normalized_title ILIKE '%cook%'
          OR label.normalized_title ILIKE '%chef%'
          OR label.normalized_title ILIKE '%kitchen%'
          OR label.normalized_title ILIKE '%dishwasher%'
          OR label.normalized_title ILIKE '%security%'
          OR label.normalized_title ILIKE '%nurse%'
          OR label.normalized_title ILIKE '%medical%'
          OR label.normalized_title ILIKE '%pharmacy%'
          OR label.normalized_title ILIKE '%therap%'
          OR label.normalized_title ILIKE '%caregiver%'
          OR label.normalized_title ILIKE '%patient care%'
          OR label.normalized_title ILIKE '%plumb%'
          OR label.normalized_title ILIKE '%electrician%'
          OR label.normalized_title ILIKE '%hvac%'
          OR label.normalized_title ILIKE '%mechanic%'
          OR label.normalized_title ILIKE '%technician%'
      )
)
SELECT
    normalized_title,
    previous_status,
    'non_target'::text AS new_status,
    NULL::text AS canonical_role,
    CASE
        WHEN title ~ '(^|[^a-z])(driver|delivery driver|truck driver|route driver|bus driver|van driver|driver helper|courier|chauffeur)([^a-z]|$)'
            THEN 'profile_avoid_driver_delivery_roles'
        WHEN title ~ '(^|[^a-z])(front desk|receptionist|concierge|guest service|guest services|hotel|hospitality|host|hostess)([^a-z]|$)'
            THEN 'profile_avoid_front_desk_hospitality_roles'
        WHEN title ~ '(^|[^a-z])(restaurant|food service|foodservice|server|bartender|barista|cook|chef|kitchen|dishwasher|crew member|grill)([^a-z]|$)'
            THEN 'profile_avoid_restaurant_food_service_roles'
        WHEN title ~ '(^|[^a-z])(security guard|security officer|loss prevention|asset protection associate|patrol officer)([^a-z]|$)'
            THEN 'profile_avoid_security_guard_roles'
        WHEN title ~ '(^|[^a-z])(nurse|nursing|physician|doctor|medical assistant|pharmacy technician|dental|therapist|therapy|psychiatrist|caregiver|patient care|veterinary|veterinarian)([^a-z]|$)'
            THEN 'profile_avoid_healthcare_support_roles'
        WHEN title ~ '(^|[^a-z])(plumber|plumbing|electrician|hvac|mechanic|maintenance tech|maintenance technician|field technician|service technician|installer|repair technician)([^a-z]|$)'
            THEN 'profile_avoid_manual_trade_roles'
    END AS decision_reason
FROM candidates
WHERE (
    title ~ '(^|[^a-z])(driver|delivery driver|truck driver|route driver|bus driver|van driver|driver helper|courier|chauffeur)([^a-z]|$)'
    OR title ~ '(^|[^a-z])(front desk|receptionist|concierge|guest service|guest services|hotel|hospitality|host|hostess)([^a-z]|$)'
    OR title ~ '(^|[^a-z])(restaurant|food service|foodservice|server|bartender|barista|cook|chef|kitchen|dishwasher|crew member|grill)([^a-z]|$)'
    OR title ~ '(^|[^a-z])(security guard|security officer|loss prevention|asset protection associate|patrol officer)([^a-z]|$)'
    OR title ~ '(^|[^a-z])(nurse|nursing|physician|doctor|medical assistant|pharmacy technician|dental|therapist|therapy|psychiatrist|caregiver|patient care|veterinary|veterinarian)([^a-z]|$)'
    OR title ~ '(^|[^a-z])(plumber|plumbing|electrician|hvac|mechanic|maintenance tech|maintenance technician|field technician|service technician|installer|repair technician)([^a-z]|$)'
);

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT update_plan.normalized_title, update_plan.previous_status, update_plan.new_status, update_plan.canonical_role,
       update_plan.decision_reason || ': candidate_profile 2026-06-28',
       'system:profile-title-rules-v2'
FROM service_frontline_title_updates update_plan
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE label.classification_status IS DISTINCT FROM 'non_target'
   OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
   OR label.canonical_role IS NOT NULL
   OR label.decision_reason IS DISTINCT FROM update_plan.decision_reason || ': candidate_profile 2026-06-28';

UPDATE jobpush.job_title_labels label
SET classification_status = update_plan.new_status,
    canonical_role = update_plan.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = update_plan.decision_reason || ': candidate_profile 2026-06-28',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM service_frontline_title_updates update_plan
WHERE label.normalized_title = update_plan.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM service_frontline_title_updates update_plan
WHERE ml.normalized_title = update_plan.normalized_title;

COMMIT;

SELECT classification_status, rule_version, decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_driver_delivery_roles%%'
   OR decision_reason LIKE 'profile_avoid_front_desk_hospitality_roles%%'
   OR decision_reason LIKE 'profile_avoid_restaurant_food_service_roles%%'
   OR decision_reason LIKE 'profile_avoid_security_guard_roles%%'
   OR decision_reason LIKE 'profile_avoid_healthcare_support_roles%%'
   OR decision_reason LIKE 'profile_avoid_manual_trade_roles%%'
GROUP BY 1, 2, 3
ORDER BY titles DESC;
