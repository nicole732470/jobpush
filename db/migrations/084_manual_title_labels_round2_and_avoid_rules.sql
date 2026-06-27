BEGIN;

-- 2026-06-27 round 2 title review import.
-- Nicole marked the second unresolved-title workbook and identified additional
-- out-of-scope families: buyer/procurement, restaurant/food service, plumbing,
-- mental-health/therapy, lab/specimen, retail beauty/styling, and non-technical
-- sales roles.

CREATE TEMP TABLE manual_title_labels_20260627_round2 (
    normalized_title TEXT PRIMARY KEY,
    classification_status TEXT NOT NULL CHECK (classification_status IN ('target', 'non_target')),
    canonical_role TEXT,
    note TEXT
) ON COMMIT DROP;

INSERT INTO manual_title_labels_20260627_round2 (
    normalized_title, classification_status, canonical_role, note
) VALUES
    ('relationship manager', 'target', NULL, NULL),
    ('senior account executive', 'non_target', NULL, NULL),
    ('supplier quality engineer', 'target', NULL, NULL),
    ('biomed service specialist field technician', 'non_target', NULL, NULL),
    ('desktop support', 'non_target', NULL, NULL),
    ('flex associate', 'non_target', NULL, NULL),
    ('personal stylist assistant', 'non_target', NULL, NULL),
    ('selling advisor', 'non_target', NULL, NULL),
    ('senior representative sales', 'non_target', NULL, NULL),
    ('account executive veterans military community', 'non_target', NULL, NULL),
    ('laboratory specimen processor', 'non_target', NULL, NULL),
    ('specimen accessioner', 'non_target', NULL, NULL),
    ('financial analyst', 'target', NULL, NULL),
    ('controls engineer', 'non_target', NULL, NULL),
    ('salesforce developer', 'target', NULL, NULL),
    ('network engineer', 'non_target', NULL, NULL),
    ('regional sales manager', 'non_target', NULL, NULL),
    ('implementation engineer', 'non_target', NULL, NULL),
    ('advance practice provider np/pa', 'non_target', NULL, NULL),
    ('behavior technician', 'non_target', NULL, NULL),
    ('lab assistant', 'non_target', NULL, NULL),
    ('shift leader', 'non_target', NULL, NULL),
    ('solar appointment setter', 'non_target', NULL, NULL),
    ('tax manager', 'non_target', NULL, NULL),
    ('technical project manager', 'target', NULL, NULL),
    ('technical support specialist', 'target', NULL, NULL),
    ('security analyst', 'target', NULL, NULL),
    ('senior analytics engineer', 'target', NULL, NULL),
    ('beauty advisor - la mer', 'non_target', NULL, NULL),
    ('beauty advisor - la prairie', 'non_target', NULL, NULL),
    ('restaurant server', 'non_target', NULL, NULL),
    ('studio associate', 'non_target', NULL, NULL),
    ('environmental driver specialist cdla', 'non_target', NULL, NULL),
    ('licensed plumbing vendors', 'non_target', NULL, NULL),
    ('engagement manager', 'non_target', NULL, NULL),
    ('data architect', 'target', NULL, NULL),
    ('infrastructure engineer', 'target', NULL, NULL),
    ('senior technical support engineer', 'target', NULL, NULL),
    ('receptionist', 'non_target', NULL, NULL),
    ('operations analyst', 'target', NULL, NULL),
    ('technician', 'non_target', NULL, NULL),
    ('deployment strategist', 'target', NULL, NULL),
    ('quantitative researcher', 'non_target', NULL, NULL),
    ('trainee', 'non_target', NULL, NULL),
    ('assembly operator', 'non_target', NULL, NULL),
    ('class b driver - 1st shift 5am to 5pm - 3 000 sign on bonus', 'non_target', NULL, NULL),
    ('histotechnician', 'non_target', NULL, NULL),
    ('hospital reference test clerk', 'non_target', NULL, NULL),
    ('j1 students only-ma-cape cod-part time seasonal', 'non_target', NULL, NULL),
    ('medical courier', 'non_target', NULL, NULL),
    ('office services associate', 'non_target', NULL, NULL),
    ('technician i managed services', 'non_target', NULL, NULL),
    ('it project manager', 'target', NULL, NULL),
    ('controller', 'non_target', NULL, NULL),
    ('gtm engineer', 'target', NULL, NULL),
    ('senior administrative assistant', 'non_target', NULL, NULL),
    ('commercial account manager', 'non_target', NULL, NULL),
    ('senior program manager', 'non_target', NULL, NULL),
    ('branch manager', 'non_target', NULL, NULL),
    ('sales analyst', 'target', NULL, NULL),
    ('bartender', 'non_target', NULL, NULL),
    ('dishwasher', 'non_target', NULL, NULL),
    ('fifth avenue club advisor', 'non_target', NULL, NULL),
    ('linux engineer', 'non_target', NULL, NULL),
    ('msl', 'non_target', NULL, NULL),
    ('restaurant assistant server', 'non_target', NULL, NULL),
    ('restaurant host', 'non_target', NULL, NULL),
    ('sr enterprise relationship manager', 'non_target', NULL, NULL),
    ('assistant site manager', 'target', NULL, NULL),
    ('counter sales associate', 'non_target', NULL, NULL),
    ('erp presales architect direct channel w/m/x microsoft dynamics 365', 'target', NULL, NULL),
    ('fulfillment packaging assistant', 'non_target', NULL, NULL),
    ('hgv driver', 'non_target', NULL, NULL),
    ('mental health provider', 'non_target', NULL, NULL),
    ('motorista de caminhão i', 'non_target', NULL, NULL),
    ('psychiatrist', 'non_target', NULL, NULL),
    ('r d engineer ic design', 'target', NULL, NULL),
    ('restaurant team member', 'non_target', NULL, NULL),
    ('senior engineer etl', 'non_target', NULL, NULL),
    ('implementation manager', 'non_target', NULL, NULL),
    ('buyer', 'non_target', NULL, NULL),
    ('it support specialist', 'target', NULL, NULL);


INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-06-27-draft-4','non_target',NULL,'buyer procurement purchasing','(^|[^a-z])(buyer|procurement buyer|purchasing|purchasing agent|sourcing buyer|category buyer|merchandise buyer)([^a-z]|$)','nicole_review_2026-06-27-round2','profile_avoid_buyer_procurement_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-4','non_target',NULL,'restaurant food service','(^|[^a-z])(restaurant|cook|chef|server|bartender|barista|food service|shift leader|kitchen|culinary|dishwasher|hostess|host)([^a-z]|$)','nicole_review_2026-06-27-round2','profile_avoid_restaurant_food_service_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-4','non_target',NULL,'plumber plumbing','(^|[^a-z])(plumber|plumbing|pipefitter|pipe fitter)([^a-z]|$)','nicole_review_2026-06-27-round2','profile_avoid_plumbing_trade_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-4','non_target',NULL,'mental health therapy','(^|[^a-z])(psychiatrist|psychiatry|psychologist|psychology|therapist|therapy|behavior technician|behavioral health|mental health|counselor|social worker)([^a-z]|$)','nicole_review_2026-06-27-round2','profile_avoid_mental_health_therapy_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-4','non_target',NULL,'lab specimen clinical support','(^|[^a-z])(laboratory specimen|specimen processor|specimen accessioner|lab assistant|lab technician|clinical laboratory|medical laboratory|biomed service specialist)([^a-z]|$)','nicole_review_2026-06-27-round2','profile_avoid_lab_specimen_clinical_support_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-4','non_target',NULL,'beauty stylist retail advisor','(^|[^a-z])(beauty advisor|personal stylist|stylist assistant|selling advisor|flex associate|alterations associate|merchandise operations associate|merchandising operations associate)([^a-z]|$)','nicole_review_2026-06-27-round2','profile_avoid_beauty_stylist_retail_roles',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-4','non_target',NULL,'non technical sales insurance loan','(^|[^a-z])(account executive|sales executive|regional sales manager|senior representative sales|insurance agent|loan sales|appointment setter|solar appointment setter)([^a-z]|$)','nicole_review_2026-06-27-round2','profile_avoid_non_technical_sales_roles',22,TRUE)
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
           manual.classification_status AS new_status,
           CASE WHEN manual.classification_status = 'target'
                THEN COALESCE(manual.canonical_role, label.canonical_role)
                ELSE NULL
           END AS canonical_role,
           'manual_title_review_round2_2026-06-27: workbook label=' || manual.classification_status AS decision_reason
    FROM manual_title_labels_20260627_round2 manual
    JOIN jobpush.job_title_labels label USING (normalized_title)
    WHERE label.classification_status IS DISTINCT FROM manual.classification_status
       OR COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
       OR label.decision_reason IS DISTINCT FROM 'manual_title_review_round2_2026-06-27: workbook label=' || manual.classification_status
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
           manual.classification_status AS new_status,
           CASE WHEN manual.classification_status = 'target'
                THEN COALESCE(manual.canonical_role, label.canonical_role)
                ELSE NULL
           END AS canonical_role,
           'manual_title_review_round2_2026-06-27: workbook label=' || manual.classification_status AS decision_reason
    FROM manual_title_labels_20260627_round2 manual
    JOIN jobpush.job_title_labels label USING (normalized_title)
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'manual-title-review-round2-2026-06-27',
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
          'profile_avoid_buyer_procurement_roles',
          'profile_avoid_restaurant_food_service_roles',
          'profile_avoid_plumbing_trade_roles',
          'profile_avoid_mental_health_therapy_roles',
          'profile_avoid_lab_specimen_clinical_support_roles',
          'profile_avoid_beauty_stylist_retail_roles',
          'profile_avoid_non_technical_sales_roles'
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
          'profile_avoid_buyer_procurement_roles',
          'profile_avoid_restaurant_food_service_roles',
          'profile_avoid_plumbing_trade_roles',
          'profile_avoid_mental_health_therapy_roles',
          'profile_avoid_lab_specimen_clinical_support_roles',
          'profile_avoid_beauty_stylist_retail_roles',
          'profile_avoid_non_technical_sales_roles'
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
