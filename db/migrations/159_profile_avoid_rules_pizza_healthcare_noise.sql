BEGIN;

-- ponytail: close obvious review noise holes; do not wait for ML on pizza/hospital/pharma titles.
INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-08-draft-17','non_target',NULL,'pizza food service roles','(^|[^a-z])(pizza|pizza maker|domino''?s?|papa john''?s?|pizzaiolo)([^a-z]|$)','title_review_noise_audit_2026-07-08','profile_avoid_pizza_food_service_roles',20,TRUE),
    ('profile-title-rules-v2','2026-07-08-draft-17','non_target',NULL,'hospital healthcare clinical pharma roles','(^|[^a-z])(hospital|hospitalist|pharma|pharmaceutical|pharmacy|pharmacist|pharmacy technician|physician|doctor|medical assistant|clinical|clinician|nurse|nursing|therapist|therapy|patient|radiology|surgical|surgeon|dental|dentist|veterinary|paramedic|laboratory technician|lab technician)([^a-z]|$)','title_review_noise_audit_2026-07-08','profile_avoid_healthcare_pharma_hospital_roles',20,TRUE)
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
           WHEN lower(label.normalized_title) ~ '(^|[^a-z])(pizza|pizza maker|domino''?s?|papa john''?s?|pizzaiolo)([^a-z]|$)'
               THEN 'profile_avoid_pizza_food_service_roles'
           ELSE 'profile_avoid_healthcare_pharma_hospital_roles'
       END AS decision_reason
FROM jobpush.job_title_labels label
WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
  AND (
      lower(label.normalized_title) ~ '(^|[^a-z])(pizza|pizza maker|domino''?s?|papa john''?s?|pizzaiolo)([^a-z]|$)'
      OR lower(label.normalized_title) ~ '(^|[^a-z])(hospital|hospitalist|pharma|pharmaceutical|pharmacy|pharmacist|pharmacy technician|physician|doctor|medical assistant|clinical|clinician|nurse|nursing|therapist|therapy|patient|radiology|surgical|surgeon|dental|dentist|veterinary|paramedic|laboratory technician|lab technician)([^a-z]|$)'
  );

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

CREATE OR REPLACE FUNCTION jobpush.title_review_cluster_key(p_title TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_title TEXT := lower(coalesce(p_title, ''));
    v_token TEXT;
    v_tokens TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF v_title ~ '(^|[^a-z])(dentist|dental|orthodont|oral surgeon|endodontist|periodontist)([^a-z]|$)' THEN
        RETURN 'svc:dental';
    ELSIF v_title ~ '(^|[^a-z])(barista|cafe|café|restaurant|server|cook|dishwasher|kitchen|food runner|busser|hostess|pizza|domino''?s?|papa john''?s?|pizzaiolo)([^a-z]|$)' THEN
        RETURN 'svc:food_restaurant';
    ELSIF v_title ~ '(^|[^a-z])(cashier|shopper|shopping|store associate|retail associate|sales floor|cart attendant|stocker|merchandise associate)([^a-z]|$)' THEN
        RETURN 'svc:retail_store';
    ELSIF v_title ~ '(^|[^a-z])(courier|carrier|delivery driver|route driver|package handler|cdl driver|truck driver|forklift)([^a-z]|$)' THEN
        RETURN 'svc:delivery_logistics';
    ELSIF v_title ~ '(^|[^a-z])(security officer|security guard|valet|bus monitor|direct support professional|care worker|caregiver)([^a-z]|$)' THEN
        RETURN 'svc:frontline_care_security';
    ELSIF v_title ~ '(^|[^a-z])(nurse|nursing|physician|doctor|therapist|medical assistant|clinical|clinician|microbiologist|resident -?pgy|chaplain|medical records|hospital|hospitalist|pharma|pharmaceutical|pharmacy|pharmacist|patient|radiology|surgical|surgeon|veterinary|paramedic)([^a-z]|$)' THEN
        RETURN 'clinical:healthcare';
    ELSIF v_title ~ '(^|[^a-z])(teacher|teaching|instructor|professor|faculty|tutor|school)([^a-z]|$)' THEN
        RETURN 'edu:teaching';
    ELSIF v_title ~ '(^|[^a-z])(attorney|lawyer|legal|paralegal|litigation|counsel)([^a-z]|$)' THEN
        RETURN 'legal:legal';
    ELSIF v_title ~ '(^|[^a-z])(cleaner|cleaning|janitor|housekeeper|sanitation)([^a-z]|$)' THEN
        RETURN 'svc:cleaning';
    ELSIF v_title ~ '(^|[^a-z])(mechanic|electrician|plumber|welder|hvac|maintenance|technician|machine operator|plant technician|corrugate)([^a-z]|$)' THEN
        RETURN 'trade:technician_operator';
    ELSIF v_title ~ '(^|[^a-z])(product manager|product owner|product analyst|product marketing)([^a-z]|$)' THEN
        RETURN 'targetish:product';
    ELSIF v_title ~ '(^|[^a-z])(data engineer|data analyst|data scientist|data modeler|business intelligence|bi analyst)([^a-z]|$)' THEN
        RETURN 'targetish:data';
    ELSIF v_title ~ '(^|[^a-z])(software engineer|software developer|developer|programmer|devops|cloud engineer|qa engineer|test engineer)([^a-z]|$)' THEN
        RETURN 'tech:sde_dev';
    ELSIF v_title ~ '(^|[^a-z])(system engineer|systems engineer|solutions engineer|solution architect|solutions architect|sales engineer)([^a-z]|$)' THEN
        RETURN 'targetish:systems_solutions';
    ELSIF v_title ~ '(^|[^a-z])(project manager|program manager|business analyst|systems analyst|implementation)([^a-z]|$)' THEN
        RETURN 'targetish:business_program';
    ELSIF v_title ~ '(^|[^a-z])(architect)([^a-z]|$)' THEN
        RETURN 'boundary:architect';
    ELSIF v_title ~ '(^|[^a-z])(manager|supervisor|director|lead|principal|head|vice president|vp)([^a-z]|$)' THEN
        RETURN 'boundary:seniority_management';
    END IF;

    FOR v_token IN
        SELECT token
        FROM regexp_split_to_table(v_title, '[^a-z0-9+#.]+') AS token
        WHERE length(token) > 2
          AND token NOT IN (
              'and','the','for','with','senior','junior','associate','assistant',
              'manager','specialist','engineer','developer','analyst','consultant',
              'coordinator','administrator','professional','level','remote',
              'full','time','part','shift','contract','intern','internship'
          )
        LIMIT 2
    LOOP
        v_tokens := array_append(v_tokens, v_token);
    END LOOP;

    IF array_length(v_tokens, 1) IS NULL THEN
        RETURN 'other:' || left(regexp_replace(v_title, '[^a-z0-9]+', '_', 'g'), 40);
    END IF;
    RETURN 'token:' || array_to_string(v_tokens, '_');
END;
$$;

COMMIT;

SELECT decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_pizza_food_service_roles%%'
   OR decision_reason LIKE 'profile_avoid_healthcare_pharma_hospital_roles%%'
GROUP BY decision_reason
ORDER BY titles DESC;
