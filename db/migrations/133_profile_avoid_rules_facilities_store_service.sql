BEGIN;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-06-30-draft-9','non_target',NULL,'benefits and customer service representative','(^|[^a-z])(employee benefits|benefits representative|benefits specialist|customer service representative|customer care representative|customer support representative|client service representative|call center representative|contact center representative)([^a-z]|$)','nicole_hard_exclusion_2026-06-30','profile_avoid_benefits_customer_service_representative',16,TRUE),
    ('profile-title-rules-v2','2026-06-30-draft-9','non_target',NULL,'aerospace aircraft engine roles','(^|[^a-z])(aerospace|aviation|aircraft|airplane|flight test|airframe|propulsion|turbine engine|aircraft engine|engine mechanic|engine technician|jet engine)([^a-z]|$)','nicole_hard_exclusion_2026-06-30','profile_avoid_aerospace_aircraft_engine_roles',16,TRUE),
    ('profile-title-rules-v2','2026-06-30-draft-9','non_target',NULL,'data center facilities roles','(^|[^a-z])(data center|datacenter|data centre|critical facilities|facility engineer|facilities engineer|facilities technician|facilities maintenance)([^a-z]|$)','nicole_hard_exclusion_2026-06-30','profile_avoid_data_center_facilities_roles',16,TRUE),
    ('profile-title-rules-v2','2026-06-30-draft-9','non_target',NULL,'electronics technician roles','(^|[^a-z])(electronics|electronic technician|electronics technician|electrical technician|avionics|pcb technician|test technician)([^a-z]|$)','nicole_hard_exclusion_2026-06-30','profile_avoid_electronics_technician_roles',16,TRUE),
    ('profile-title-rules-v2','2026-06-30-draft-9','non_target',NULL,'networking engineer roles','(^|[^a-z])(networking engineer|network engineer|network operations engineer|noc engineer|network technician)([^a-z]|$)','nicole_hard_exclusion_2026-06-30','profile_avoid_networking_engineer_roles',16,TRUE),
    ('profile-title-rules-v2','2026-06-30-draft-9','non_target',NULL,'supervisor titles','(^|[^a-z])(supervisor|shift supervisor|operations supervisor|store supervisor|area supervisor|team supervisor)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels + nicole_hard_exclusion_2026-06-30','profile_hard_supervisor_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-30-draft-9','non_target',NULL,'maintenance repair technician trades','(^|[^a-z])(maintenance|repair|technician|mechanic|field service|service technician|maintenance engineer|maintenance manager|maintenance planner|维修|技工)([^a-z]|$)','nicole_hard_exclusion_2026-06-30','profile_avoid_maintenance_repair_technician_trades',16,TRUE),
    ('profile-title-rules-v2','2026-06-30-draft-9','non_target',NULL,'pure scientist mathematician titles','(^|[^a-z])(mathematician|physicist|chemist|biologist|geologist|astronomer|statistician|actuary)([^a-z]|$)','nicole_hard_exclusion_2026-06-30','profile_avoid_pure_scientist_titles',16,TRUE),
    ('profile-title-rules-v2','2026-06-30-draft-9','non_target',NULL,'store frontline service roles','(^|[^a-z])(store associate|store manager|assistant store manager|store supervisor|store employee|store sales|store worker|in[- ]store|retail store|retail associate|retail manager|retail supervisor)([^a-z]|$)','nicole_hard_exclusion_2026-06-30','profile_avoid_store_frontline_service_roles',16,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE title_hard_exclusion_updates_20260630 ON COMMIT DROP AS
WITH rules(decision_reason, regex_pattern) AS (
    VALUES
      ('profile_avoid_benefits_customer_service_representative', '(^|[^a-z])(employee benefits|benefits representative|benefits specialist|customer service representative|customer care representative|customer support representative|client service representative|call center representative|contact center representative)([^a-z]|$)'),
      ('profile_avoid_aerospace_aircraft_engine_roles', '(^|[^a-z])(aerospace|aviation|aircraft|airplane|flight test|airframe|propulsion|turbine engine|aircraft engine|engine mechanic|engine technician|jet engine)([^a-z]|$)'),
      ('profile_avoid_data_center_facilities_roles', '(^|[^a-z])(data center|datacenter|data centre|critical facilities|facility engineer|facilities engineer|facilities technician|facilities maintenance)([^a-z]|$)'),
      ('profile_avoid_electronics_technician_roles', '(^|[^a-z])(electronics|electronic technician|electronics technician|electrical technician|avionics|pcb technician|test technician)([^a-z]|$)'),
      ('profile_avoid_networking_engineer_roles', '(^|[^a-z])(networking engineer|network engineer|network operations engineer|noc engineer|network technician)([^a-z]|$)'),
      ('profile_hard_supervisor_exclusion', '(^|[^a-z])(supervisor|shift supervisor|operations supervisor|store supervisor|area supervisor|team supervisor)([^a-z]|$)'),
      ('profile_avoid_maintenance_repair_technician_trades', '(^|[^a-z])(maintenance|repair|technician|mechanic|field service|service technician|maintenance engineer|maintenance manager|maintenance planner|维修|技工)([^a-z]|$)'),
      ('profile_avoid_pure_scientist_titles', '(^|[^a-z])(mathematician|physicist|chemist|biologist|geologist|astronomer|statistician|actuary)([^a-z]|$)'),
      ('profile_avoid_store_frontline_service_roles', '(^|[^a-z])(store associate|store manager|assistant store manager|store supervisor|store employee|store sales|store worker|in[- ]store|retail store|retail associate|retail manager|retail supervisor)([^a-z]|$)')
), matches AS (
    SELECT DISTINCT ON (label.normalized_title)
           label.normalized_title,
           label.classification_status AS previous_status,
           rules.decision_reason
    FROM jobpush.job_title_labels label
    JOIN rules
      ON lower(label.normalized_title) ~ rules.regex_pattern
    ORDER BY label.normalized_title,
             CASE rules.decision_reason
               WHEN 'profile_hard_supervisor_exclusion' THEN 0
               ELSE 1
             END,
             rules.decision_reason
)
SELECT matches.normalized_title,
       label.classification_status AS previous_status,
       'non_target'::text AS new_status,
       NULL::text AS canonical_role,
       matches.decision_reason
FROM jobpush.job_title_labels label
JOIN matches USING (normalized_title)
WHERE (label.classification_status IS DISTINCT FROM 'non_target'
       OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
       OR label.canonical_role IS NOT NULL
       OR label.decision_reason IS DISTINCT FROM matches.decision_reason || ': candidate_profile 2026-06-30');

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-06-30',
       'system:profile-title-rules-v2'
FROM title_hard_exclusion_updates_20260630;

UPDATE jobpush.job_title_labels label
SET classification_status = update_plan.new_status,
    canonical_role = update_plan.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = update_plan.decision_reason || ': candidate_profile 2026-06-30',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM title_hard_exclusion_updates_20260630 update_plan
WHERE label.normalized_title = update_plan.normalized_title;

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM title_hard_exclusion_updates_20260630 update_plan
WHERE ml.normalized_title = update_plan.normalized_title;

COMMIT;

SELECT decision_reason, count(*) AS updated_titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile\_%: candidate_profile 2026-06-30' ESCAPE '\'
GROUP BY decision_reason
ORDER BY updated_titles DESC, decision_reason;

SELECT classification_status, COALESCE(rule_version, 'unknown') AS rule_version, count(*) AS titles
FROM jobpush.job_title_labels
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT count(*) AS remaining_review_titles
FROM jobpush.job_title_review_queue;

SELECT count(*) AS open_target_jobs
FROM jobpush.dashboard_jobs
WHERE role_status = 'target'
  AND application_status IN ('new','saved','apply_next','referred');
