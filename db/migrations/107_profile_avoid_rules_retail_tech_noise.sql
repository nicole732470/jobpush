BEGIN;

-- Reduce title-review noise from the 2026-06-28 high-volume audit.
-- ponytail: deterministic hard-avoid rules only; no broad manager/architect rule
-- because those collide with Product Manager and Solutions Architect targets.

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-06-28-draft-12','non_target',NULL,'retail grocery fresh department roles','(^|[^a-z])(produce clerk|produce manager|deli clerk|deli manager|floral clerk|floral designer|floral manager|bakery clerk|bakery manager|meat manager|grocery manager|beverage steward|stock associate|stock clerk|file maintenance clerk|third person in charge)([^a-z]|$)','title_review_noise_audit_2026-06-28','profile_avoid_retail_grocery_department_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-28-draft-12','non_target',NULL,'frontline team member associate','(^|[^a-z])(team member|crew member|sales and service rep|customer service associate|delivery station customer service associate|service supervisor|night crew supervisor|fleet supervisor|fleet manager)([^a-z]|$)','title_review_noise_audit_2026-06-28','profile_avoid_frontline_service_titles',18,TRUE),
    ('profile-title-rules-v2','2026-06-28-draft-12','non_target',NULL,'technician apprentice wirer','(^|[^a-z])(technician|techniker|tech compute services|wirer|apprentice|installer|estimator)([^a-z]|$)','title_review_noise_audit_2026-06-28','profile_avoid_technician_trade_titles',18,TRUE),
    ('profile-title-rules-v2','2026-06-28-draft-12','non_target',NULL,'non-us short markers m/w portuguese','(^|[^a-z])(m/w|m/w/d|auxiliar de servi[cç]os gerais|servi[cç]os gerais)([^a-z]|$)','title_review_noise_audit_2026-06-28','profile_non_us_market_or_language_marker',12,TRUE),
    ('profile-title-rules-v2','2026-06-28-draft-12','non_target',NULL,'producer media role','(^|[^a-z])(producer|content producer|video producer)([^a-z]|$)','title_review_noise_audit_2026-06-28','profile_avoid_producer_media_roles',18,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE title_noise_updates ON COMMIT DROP AS
WITH proposed AS (
    SELECT label.normalized_title,
           label.classification_status AS previous_status,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status = 'non_target'
      AND decision.decision_reason IN (
          'profile_avoid_retail_grocery_department_roles',
          'profile_avoid_frontline_service_titles',
          'profile_avoid_technician_trade_titles',
          'profile_non_us_market_or_language_marker',
          'profile_avoid_producer_media_roles'
      )
)
SELECT * FROM proposed;

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT update_plan.normalized_title, update_plan.previous_status, update_plan.new_status, update_plan.canonical_role,
       update_plan.decision_reason || ': candidate_profile 2026-06-28',
       'system:profile-title-rules-v2'
FROM title_noise_updates update_plan
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE label.classification_status IS DISTINCT FROM update_plan.new_status
   OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
   OR label.canonical_role IS DISTINCT FROM update_plan.canonical_role
   OR label.decision_reason IS DISTINCT FROM update_plan.decision_reason || ': candidate_profile 2026-06-28';

UPDATE jobpush.job_title_labels label
SET classification_status = update_plan.new_status,
    canonical_role = update_plan.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = update_plan.decision_reason || ': candidate_profile 2026-06-28',
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

SELECT classification_status, rule_version, decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_retail_grocery_department_roles%%'
   OR decision_reason LIKE 'profile_avoid_frontline_service_titles%%'
   OR decision_reason LIKE 'profile_avoid_technician_trade_titles%%'
   OR decision_reason LIKE 'profile_non_us_market_or_language_marker%%'
   OR decision_reason LIKE 'profile_avoid_producer_media_roles%%'
GROUP BY 1, 2, 3
ORDER BY titles DESC;
