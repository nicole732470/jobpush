BEGIN;

-- ponytail: deterministic cleanup for high-volume noise seen in Amazon,
-- Domino/SmartRecruiters, and staffing-style boards. Keep this narrow; do not
-- turn every "manager" into non-target because Product Manager is allowed.
INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-09-draft-18','non_target',NULL,'old enterprise middleware stack','(^|[^a-z])(informatica mdm|microsoft dynamics crm|adobe aem|cq5|oracle data integrator|\\bodi\\b|curam|pega|oracle commerce|\\batg\\b|microstrategy|datapower|datastage|teradata|cobol|mainframe|jda supply chain|manhattan wmos|openspan|websphere message broker|\\bwmb\\b)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_old_enterprise_stack',22,TRUE),
    ('profile-title-rules-v2','2026-07-09-draft-18','non_target',NULL,'non product manager roles','(^|[^a-z])(operations manager|finance manager|pre-construction manager|contract manager|regulatory affairs manager|branch manager|assistant operations manager|site manager|relationship manager|account manager|partner success manager|district manager|kitchen manager|store manager|front office manager|customer service manager|self storage manager)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_non_product_manager_roles',22,TRUE),
    ('profile-title-rules-v2','2026-07-09-draft-18','non_target',NULL,'amazon ops language planner roles','(^|[^a-z])(escalations specialist - (spanish|portuguese)|rme operator|nw deployment planner|nw deployment build mgr|ops tech solutions|\\bots\\b|pre-construction manager|relo ops|worldwide operations security)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_amazon_ops_language_planner_roles',22,TRUE),
    ('profile-title-rules-v2','2026-07-09-draft-18','non_target',NULL,'frontline retail food service board roles','(^|[^a-z])(domino''?s?|pizza maker|delivery expert|restaurant team member|restaurant assistant server|restaurant host|bartender|dishwasher|floor tech|deli assistant manager|counter sales associate|fulfillment packaging assistant|store|in-store|instore)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_frontline_retail_food_service_roles',22,TRUE),
    ('profile-title-rules-v2','2026-07-09-draft-18','non_target',NULL,'staffing senior architect niche stack roles','(^|[^a-z])(java architect|big data architect|microservices architect|servicenow architect|salesforce integration architect|data platform architect|aws architect|cloud architect|sap basis|sap fiori|sap hana|sap security|sap btp|sap cpi|sap abap|dell boomi|mulesoft|peoplesoft|guidewire|sitecore|windchill|ptc windchill|vmware|storage engineer|network automation engineer|openshift platform engineer)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_staffing_niche_stack_roles',22,TRUE)
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
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(informatica mdm|microsoft dynamics crm|adobe aem|cq5|oracle data integrator|\bodi\b|curam|pega|oracle commerce|\batg\b|microstrategy|datapower|datastage|teradata|cobol|mainframe|jda supply chain|manhattan wmos|openspan|websphere message broker|\bwmb\b)([^a-z]|$)'
               THEN 'profile_avoid_old_enterprise_stack'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(operations manager|finance manager|pre-construction manager|contract manager|regulatory affairs manager|branch manager|assistant operations manager|site manager|relationship manager|account manager|partner success manager|district manager|kitchen manager|store manager|front office manager|customer service manager|self storage manager)([^a-z]|$)'
                AND lower(label.normalized_title) !~ '(^|[^a-z])(product manager|technical product manager)([^a-z]|$)'
               THEN 'profile_avoid_non_product_manager_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(escalations specialist - (spanish|portuguese)|rme operator|nw deployment planner|nw deployment build mgr|ops tech solutions|\bots\b|pre-construction manager|relo ops|worldwide operations security)([^a-z]|$)'
               THEN 'profile_avoid_amazon_ops_language_planner_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(domino''?s?|pizza maker|delivery expert|restaurant team member|restaurant assistant server|restaurant host|bartender|dishwasher|floor tech|deli assistant manager|counter sales associate|fulfillment packaging assistant|store|in-store|instore)([^a-z]|$)'
               THEN 'profile_avoid_frontline_retail_food_service_roles'
           ELSE 'profile_avoid_staffing_niche_stack_roles'
       END AS decision_reason
FROM jobpush.job_title_labels label
WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
  AND (
      lower(label.normalized_title) ~ '(^|[^a-z])(informatica mdm|microsoft dynamics crm|adobe aem|cq5|oracle data integrator|\bodi\b|curam|pega|oracle commerce|\batg\b|microstrategy|datapower|datastage|teradata|cobol|mainframe|jda supply chain|manhattan wmos|openspan|websphere message broker|\bwmb\b)([^a-z]|$)'
      OR (
          lower(label.normalized_title) ~ '(^|[^a-z])(operations manager|finance manager|pre-construction manager|contract manager|regulatory affairs manager|branch manager|assistant operations manager|site manager|relationship manager|account manager|partner success manager|district manager|kitchen manager|store manager|front office manager|customer service manager|self storage manager)([^a-z]|$)'
          AND lower(label.normalized_title) !~ '(^|[^a-z])(product manager|technical product manager)([^a-z]|$)'
      )
      OR lower(label.normalized_title) ~ '(^|[^a-z])(escalations specialist - (spanish|portuguese)|rme operator|nw deployment planner|nw deployment build mgr|ops tech solutions|\bots\b|pre-construction manager|relo ops|worldwide operations security)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(domino''?s?|pizza maker|delivery expert|restaurant team member|restaurant assistant server|restaurant host|bartender|dishwasher|floor tech|deli assistant manager|counter sales associate|fulfillment packaging assistant|store|in-store|instore)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(java architect|big data architect|microservices architect|servicenow architect|salesforce integration architect|data platform architect|aws architect|cloud architect|sap basis|sap fiori|sap hana|sap security|sap btp|sap cpi|sap abap|dell boomi|mulesoft|peoplesoft|guidewire|sitecore|windchill|ptc windchill|vmware|storage engineer|network automation engineer|openshift platform engineer)([^a-z]|$)'
  );

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT update_plan.normalized_title, update_plan.previous_status, update_plan.new_status, update_plan.canonical_role,
       update_plan.decision_reason || ': candidate_profile 2026-07-09',
       'system:profile-title-rules-v2'
FROM title_noise_updates update_plan
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE label.classification_status IS DISTINCT FROM update_plan.new_status
   OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
   OR label.canonical_role IS DISTINCT FROM update_plan.canonical_role
   OR label.decision_reason IS DISTINCT FROM update_plan.decision_reason || ': candidate_profile 2026-07-09';

UPDATE jobpush.job_title_labels label
SET classification_status = update_plan.new_status,
    canonical_role = update_plan.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = update_plan.decision_reason || ': candidate_profile 2026-07-09',
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

-- Domino boards are huge frontline boards with no useful target yield. Pause
-- them instead of paying to re-crawl 20k+ postings repeatedly.
UPDATE jobpush.career_sites site
SET crawl_enabled = FALSE,
    crawl_status = 'paused',
    verification_status = CASE
        WHEN site.reviewed_by LIKE 'system:%' THEN 'unverified'
        ELSE site.verification_status
    END,
    review_notes = concat_ws('; ', site.review_notes, 'Paused high-volume frontline Domino SmartRecruiters board (migration 160)'),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND site.source_type = 'smartrecruiters'
  AND site.crawl_enabled
  AND (
      lower(target.canonical_name) LIKE '%domino%pizza%'
      OR lower(site.site_url) LIKE '%dominos%'
  );

COMMIT;

SELECT regexp_replace(decision_reason, ': candidate_profile 2026-07-09$', '') AS reason,
       count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile\_avoid\_%candidate\_profile 2026-07-09' ESCAPE '\'
GROUP BY 1
ORDER BY titles DESC;

SELECT site.source_type, site.crawl_status, site.crawl_enabled, count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE lower(target.canonical_name) LIKE '%domino%pizza%'
   OR lower(site.site_url) LIKE '%dominos%'
GROUP BY 1,2,3
ORDER BY 1,2,3;
