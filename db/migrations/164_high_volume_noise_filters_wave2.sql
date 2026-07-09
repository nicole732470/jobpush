BEGIN;

-- ponytail: second pass from post-160 audit. SDE/support/infra/niche staffing
-- are not Jobs-to-Apply targets under the current profile.
INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-09-draft-19','non_target',NULL,'sde software engineering roles','(^|[^a-z])(software development engineer|software dev engineer|software engineer|\\bsde\\b)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_sde_software_engineering_roles',24,TRUE),
    ('profile-title-rules-v2','2026-07-09-draft-19','non_target',NULL,'it support helpdesk ots roles','(^|[^a-z])(it support engineer|it support specialist|help desk|helpdesk|ops tech solutions|\\bots\\b|support engineer i)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_it_support_helpdesk_ots_roles',24,TRUE),
    ('profile-title-rules-v2','2026-07-09-draft-19','non_target',NULL,'infra construction hardware ops roles','(^|[^a-z])(network infrastructure engineer|construction cost engineer|controls manager|area manager|operations engineer|hw dev engineer|hardware|payload|rme operator|schedule controls manager|data center|datacenter)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_infra_construction_hardware_ops_roles',24,TRUE),
    ('profile-title-rules-v2','2026-07-09-draft-19','non_target',NULL,'sales account demand generation rep roles','(^|[^a-z])(strategic demand generation representative|account representative|community engagement manager|sales representative|business development representative|\\bbdr\\b|\\bsdr\\b)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_sales_account_demand_generation_rep_roles',24,TRUE),
    ('profile-title-rules-v2','2026-07-09-draft-19','non_target',NULL,'staffing ai infra niche roles','(^|[^a-z])(llm engineer|mlops engineer|ml infrastructure engineer|model serving engineer|prompt engineer|prompt engineering|ai pipeline engineer|ai performance engineer|iot engineer|industrial iot|kafka engineer|hadoop big data developer|hadoop solutions developer|infrastructure automation engineer|platform automation engineer|container platform engineer|service mesh engineer)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_staffing_ai_infra_niche_roles',24,TRUE),
    ('profile-title-rules-v2','2026-07-09-draft-19','non_target',NULL,'staffing enterprise app niche roles','(^|[^a-z])(workday developer|workday integration developer|workday integration engineer|workday technical developer|coupa integration|oracle cloud integration|oracle integration cloud|\\boic\\b|crm integration architect|crm technical architect|salesforce platform developer|salesforce technical developer|\\.net developer .*wonderware)([^a-z]|$)','high_volume_noise_audit_2026-07-09','profile_avoid_staffing_enterprise_app_niche_roles',24,TRUE)
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
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(software development engineer|software dev engineer|software engineer|\bsde\b)([^a-z]|$)'
               THEN 'profile_avoid_sde_software_engineering_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(it support engineer|it support specialist|help desk|helpdesk|ops tech solutions|\bots\b|support engineer i)([^a-z]|$)'
               THEN 'profile_avoid_it_support_helpdesk_ots_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(network infrastructure engineer|construction cost engineer|controls manager|area manager|operations engineer|hw dev engineer|hardware|payload|rme operator|schedule controls manager|data center|datacenter)([^a-z]|$)'
               THEN 'profile_avoid_infra_construction_hardware_ops_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(strategic demand generation representative|account representative|community engagement manager|sales representative|business development representative|\bbdr\b|\bsdr\b)([^a-z]|$)'
               THEN 'profile_avoid_sales_account_demand_generation_rep_roles'
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(llm engineer|mlops engineer|ml infrastructure engineer|model serving engineer|prompt engineer|prompt engineering|ai pipeline engineer|ai performance engineer|iot engineer|industrial iot|kafka engineer|hadoop big data developer|hadoop solutions developer|infrastructure automation engineer|platform automation engineer|container platform engineer|service mesh engineer)([^a-z]|$)'
               THEN 'profile_avoid_staffing_ai_infra_niche_roles'
           ELSE 'profile_avoid_staffing_enterprise_app_niche_roles'
       END AS decision_reason
FROM jobpush.job_title_labels label
WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
  AND (
      lower(label.normalized_title) ~ '(^|[^a-z])(software development engineer|software dev engineer|software engineer|\bsde\b)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(it support engineer|it support specialist|help desk|helpdesk|ops tech solutions|\bots\b|support engineer i)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(network infrastructure engineer|construction cost engineer|controls manager|area manager|operations engineer|hw dev engineer|hardware|payload|rme operator|schedule controls manager|data center|datacenter)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(strategic demand generation representative|account representative|community engagement manager|sales representative|business development representative|\bbdr\b|\bsdr\b)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(llm engineer|mlops engineer|ml infrastructure engineer|model serving engineer|prompt engineer|prompt engineering|ai pipeline engineer|ai performance engineer|iot engineer|industrial iot|kafka engineer|hadoop big data developer|hadoop solutions developer|infrastructure automation engineer|platform automation engineer|container platform engineer|service mesh engineer)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(workday developer|workday integration developer|workday integration engineer|workday technical developer|coupa integration|oracle cloud integration|oracle integration cloud|\boic\b|crm integration architect|crm technical architect|salesforce platform developer|salesforce technical developer|\.net developer .*wonderware)([^a-z]|$)'
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

COMMIT;

SELECT regexp_replace(decision_reason, ': candidate_profile 2026-07-09$', '') AS reason,
       count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_%candidate_profile 2026-07-09'
   OR decision_reason LIKE 'profile\_avoid\_%candidate\_profile 2026-07-09' ESCAPE '\'
GROUP BY 1
ORDER BY titles DESC;
