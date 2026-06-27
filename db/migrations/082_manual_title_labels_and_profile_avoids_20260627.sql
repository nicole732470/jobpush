BEGIN;

-- 2026-06-27 Nicole reviewed the remaining title-review workbook.
-- Import exact manual title labels, then add broader non-target profile rules
-- for healthcare, legal, teaching, and skilled-trade roles so similar titles
-- do not keep coming back for manual review.

CREATE TEMP TABLE manual_title_labels_20260627 (
    normalized_title TEXT PRIMARY KEY,
    classification_status TEXT NOT NULL CHECK (classification_status IN ('target', 'non_target')),
    canonical_role TEXT,
    note TEXT
) ON COMMIT DROP;

INSERT INTO manual_title_labels_20260627 (
    normalized_title, classification_status, canonical_role, note
) VALUES
    ('pharmacy technician', 'non_target', NULL, NULL),
    ('pharmacy intern', 'non_target', NULL, NULL),
    ('registered nurse', 'non_target', NULL, NULL),
    ('patient care technician', 'non_target', NULL, NULL),
    ('grad pharmacist', 'non_target', NULL, NULL),
    ('customer service - self storage manager', 'non_target', NULL, NULL),
    ('foreign pharmacy grad - international pharmacy intern', 'non_target', NULL, NULL),
    ('phlebotomist', 'non_target', NULL, NULL),
    ('district support pharmacist full time', 'non_target', NULL, NULL),
    ('operations manager', 'non_target', NULL, NULL),
    ('pharmacy manager', 'non_target', NULL, NULL),
    ('district support pharmacist part time', 'non_target', NULL, NULL),
    ('primary care physician', 'non_target', NULL, NULL),
    ('dietitian', 'non_target', NULL, NULL),
    ('medical scribe', 'non_target', NULL, NULL),
    ('registered dietitian', 'non_target', NULL, NULL),
    ('pharmacist - full time', 'non_target', NULL, NULL),
    ('district support pharmacist', 'non_target', NULL, NULL),
    ('pharmacist', 'non_target', NULL, NULL),
    ('licensed practical nurse', 'non_target', NULL, NULL),
    ('healthcare operations manager', 'non_target', NULL, NULL),
    ('district manager', 'non_target', NULL, NULL),
    ('phlebotomist float', 'non_target', NULL, NULL),
    ('social worker', 'non_target', NULL, NULL),
    ('facility administrator', 'non_target', NULL, NULL),
    ('nurse practitioner', 'non_target', NULL, NULL),
    ('asset protection coordinator', 'non_target', NULL, NULL),
    ('advanced practice provider np/pa', 'non_target', NULL, NULL),
    ('selling advisor - contemporary', 'non_target', NULL, NULL),
    ('nurse practitioner advanced practice provider', 'non_target', NULL, NULL),
    ('pharmacy intern - grad', 'non_target', NULL, NULL),
    ('selling advisor - jewelry', 'non_target', NULL, NULL),
    ('clinical coordinator', 'non_target', NULL, NULL),
    ('sr. professional medical representative', 'non_target', NULL, NULL),
    ('alterations associate', 'non_target', NULL, NULL),
    ('merchandise operations associate', 'non_target', NULL, NULL),
    ('registered nurse rn', 'non_target', NULL, NULL),
    ('restaurant cook', 'non_target', NULL, NULL),
    ('selling advisor - handbags', 'non_target', NULL, NULL),
    ('district support pharmacist - full time', 'non_target', NULL, NULL),
    ('java developer', 'target', NULL, NULL),
    ('clinical laboratory technologist', 'non_target', NULL, NULL),
    ('operations manager-ca', 'non_target', NULL, NULL),
    ('senior engineer', 'non_target', NULL, NULL),
    ('asset protection investigator', 'non_target', NULL, NULL),
    ('merchandising operations associate', 'non_target', NULL, NULL),
    ('medical assistant', 'non_target', NULL, NULL),
    ('asset protection associate', 'non_target', NULL, NULL),
    ('selling advisor - men s', 'non_target', NULL, NULL),
    ('insurance agent', 'non_target', NULL, NULL),
    ('specimen processor i', 'non_target', NULL, NULL),
    ('sr. software development engineer', 'target', NULL, NULL),
    ('sleep expert - sales', 'non_target', NULL, NULL),
    ('sr medical infocomm rep - medical aesth', 'non_target', NULL, NULL),
    ('material handler', 'non_target', NULL, NULL),
    ('.net developer', 'target', NULL, NULL),
    ('loan sales specialist', 'non_target', NULL, NULL),
    ('environmental technician i', 'non_target', NULL, NULL),
    ('project engineer', 'target', NULL, NULL),
    ('district support pharmacist - ft', 'non_target', NULL, NULL),
    ('patient care technician pct', 'non_target', NULL, NULL),
    ('delivery driver', 'non_target', NULL, NULL),
    ('assistant branch manager', 'non_target', NULL, NULL),
    ('delivery driver - full time', 'non_target', NULL, NULL),
    ('delivery driver - part time', 'non_target', NULL, NULL),
    ('site reliability engineer', 'target', NULL, NULL),
    ('fifth avenue club assistant', 'non_target', NULL, NULL),
    ('night pharmacist full time', 'non_target', NULL, NULL),
    ('senior site reliability engineer', 'non_target', NULL, NULL),
    ('business development manager', 'target', NULL, NULL),
    ('district support pharmacist ft', 'non_target', NULL, NULL),
    ('strategic account manager', 'non_target', NULL, NULL),
    ('technical writer', 'non_target', NULL, NULL),
    ('merchandising operations associate - pt hours', 'non_target', NULL, NULL),
    ('part time brand ambassador', 'non_target', NULL, NULL),
    ('selling advisor - women s shoes', 'non_target', NULL, NULL),
    ('district support pharmacist - pt', 'non_target', NULL, NULL),
    ('registered nurse - acute dialysis rn', 'non_target', NULL, NULL),
    ('sales executive', 'non_target', NULL, NULL),
    ('senior software development engineer', 'non_target', NULL, NULL),
    ('customer service technician', 'target', NULL, NULL),
    ('sr software development engineer', 'target', NULL, NULL),
    ('ca pharmacy manager', 'non_target', NULL, NULL),
    ('clinical patient care tech paid training growth path', 'non_target', NULL, NULL),
    ('district support pharmacist - part time', 'non_target', NULL, NULL),
    ('phlebotomist - float', 'non_target', NULL, NULL),
    ('sales development executive', 'non_target', NULL, NULL),
    ('physician assistant', 'non_target', NULL, NULL),
    ('pharmacist - part time', 'non_target', NULL, NULL),
    ('pharmacy technician back end', 'non_target', NULL, NULL),
    ('welcome coordinator', 'non_target', NULL, NULL),
    ('ca district support pharmacist pt', 'non_target', NULL, NULL),
    ('district support pharmacist pt', 'non_target', NULL, NULL),
    ('hospital dialysis registered nurse', 'non_target', NULL, NULL),
    ('senior network engineer', 'non_target', NULL, NULL);


INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-06-27-draft-3','non_target',NULL,'healthcare clinical roles','(^|[^a-z])(pharmacy|pharmacist|pharmacy technician|pharmacy intern|registered nurse|licensed practical nurse|nurse|nursing|physician|primary care physician|doctor|medical assistant|medical scribe|patient care|patient service|clinical|clinician|phlebotomist|dietitian|nutritionist|therapist|radiolog|dental|caregiver|veterinar|paramedic|laboratory technician)([^a-z]|$)','nicole_review_2026-06-27','profile_avoid_healthcare_clinical_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-3','non_target',NULL,'legal roles','(^|[^a-z])(attorney|lawyer|legal counsel|counsel|paralegal|legal assistant|litigation|contract attorney|law clerk|compliance counsel)([^a-z]|$)','nicole_review_2026-06-27','profile_avoid_legal_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-3','non_target',NULL,'teacher education roles','(^|[^a-z])(teacher|teaching|instructor|professor|faculty|lecturer|tutor|curriculum specialist|education specialist|school counselor|academic advisor)([^a-z]|$)','nicole_review_2026-06-27','profile_avoid_teaching_education_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-3','non_target',NULL,'skilled trades roles','(^|[^a-z])(mechanic|electrician|plumber|welder|carpenter|hvac|installer|machinist|diesel technician|automotive technician|maintenance technician|field service technician|repair technician|equipment technician|service technician)([^a-z]|$)','nicole_review_2026-06-27','profile_avoid_skilled_trade_roles',18,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

WITH proposed AS (
    SELECT manual.normalized_title,
           label.classification_status AS previous_status,
           CASE
               WHEN manual.classification_status = 'target'
                    AND decision.classification_status = 'non_target'
                    THEN 'non_target'
               ELSE manual.classification_status
           END AS new_status,
           CASE
               WHEN manual.classification_status = 'target'
                    AND decision.classification_status <> 'non_target'
                    THEN COALESCE(manual.canonical_role, label.canonical_role)
               ELSE NULL
           END AS canonical_role,
           CASE
               WHEN manual.classification_status = 'target'
                    AND decision.classification_status = 'non_target'
                    THEN decision.decision_reason || ': hard profile rule overrides workbook target label 2026-06-27'
               ELSE 'manual_title_review_2026-06-27: workbook label=' || manual.classification_status
           END AS decision_reason
    FROM manual_title_labels_20260627 manual
    JOIN jobpush.job_title_labels label USING (normalized_title)
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(manual.normalized_title) decision
    WHERE label.classification_status IS DISTINCT FROM (
        CASE
            WHEN manual.classification_status = 'target'
                 AND decision.classification_status = 'non_target'
                 THEN 'non_target'
            ELSE manual.classification_status
        END
    )
       OR COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
       OR label.decision_reason IS DISTINCT FROM (
        CASE
            WHEN manual.classification_status = 'target'
                 AND decision.classification_status = 'non_target'
                 THEN decision.decision_reason || ': hard profile rule overrides workbook target label 2026-06-27'
            ELSE 'manual_title_review_2026-06-27: workbook label=' || manual.classification_status
        END
       )
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason, 'nicole'
FROM proposed;

WITH proposed AS (
    SELECT manual.normalized_title,
           CASE
               WHEN manual.classification_status = 'target'
                    AND decision.classification_status = 'non_target'
                    THEN 'non_target'
               ELSE manual.classification_status
           END AS new_status,
           CASE
               WHEN manual.classification_status = 'target'
                    AND decision.classification_status <> 'non_target'
                    THEN COALESCE(manual.canonical_role, label.canonical_role)
               ELSE NULL
           END AS canonical_role,
           CASE
               WHEN manual.classification_status = 'target'
                    AND decision.classification_status = 'non_target'
                    THEN decision.decision_reason || ': hard profile rule overrides workbook target label 2026-06-27'
               ELSE 'manual_title_review_2026-06-27: workbook label=' || manual.classification_status
           END AS decision_reason
    FROM manual_title_labels_20260627 manual
    JOIN jobpush.job_title_labels label USING (normalized_title)
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(manual.normalized_title) decision
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'manual-title-review-2026-06-27',
    decision_reason = proposed.decision_reason,
    labeled_by = 'nicole',
    labeled_at = now(),
    updated_at = now()
FROM proposed
WHERE label.normalized_title = proposed.normalized_title;

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
          'profile_avoid_healthcare_clinical_roles',
          'profile_avoid_legal_roles',
          'profile_avoid_teaching_education_roles',
          'profile_avoid_skilled_trade_roles'
      )
      AND (label.classification_status IS DISTINCT FROM 'non_target'
           OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
           OR label.decision_reason IS DISTINCT FROM decision.decision_reason || ': candidate_profile 2026-06-27')
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-06-27',
       'system:profile-title-rules-v2'
FROM proposed;

WITH proposed AS (
    SELECT label.normalized_title,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status = 'non_target'
      AND decision.decision_reason IN (
          'profile_avoid_healthcare_clinical_roles',
          'profile_avoid_legal_roles',
          'profile_avoid_teaching_education_roles',
          'profile_avoid_skilled_trade_roles'
      )
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = proposed.decision_reason || ': candidate_profile 2026-06-27',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM proposed
WHERE label.normalized_title = proposed.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

COMMIT;

-- rows 95
