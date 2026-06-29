BEGIN;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-06-27-draft-2','non_target',NULL,'leader','(^|[^a-z])(leader)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-2','non_target',NULL,'required non english non chinese language','(^|[^a-z])((bilingual|fluent|native|speaking|language|required|must have|must speak)[^a-z]{0,20}(spanish|japanese|korean|german|french|portuguese)|(spanish|japanese|korean|german|french|portuguese)[^a-z]{0,20}(bilingual|fluent|native|speaking|language|required))([^a-z]|$)','candidate_profile.required_languages.excluded_if_required','profile_avoid_required_non_english_non_chinese_language',12,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-2','non_target',NULL,'pure non python sde','(^|[^a-z])(java developer|java software engineer|c\\+\\+ developer|c\\+\\+ software engineer|c# developer|c# software engineer|golang developer|go developer|embedded software engineer)([^a-z]|$)','candidate_profile.avoid_tracks.pure_sde','profile_avoid_pure_non_python_sde',18,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-2','non_target',NULL,'naval aerospace engineering','(^|[^a-z])(naval|aerospace)([^a-z]|$)','candidate_profile.avoid_tracks.pure_eng','profile_hard_technical_exclusion',20,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-2','target','candidate_profile_track: product','ai technical product','(^|[^a-z])(ai product|technical product|ai implementation|ai automation|ai operations)([^a-z]|$)','candidate_profile.tracks.pm_eng','profile_target_product_track',50,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-2','target','candidate_profile_track: solutions/systems','presales engineering','(^|[^a-z])(presale engineer|presales engineer|pre sales engineer|pre-sales engineer)([^a-z]|$)','candidate_profile.tracks.pm_eng','profile_target_solutions_track',50,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-2','target','candidate_profile_track: applied_ai','gtm engineering','(^|[^a-z])(gtm engineering|gtm engineer)([^a-z]|$)','candidate_profile.tracks.ai_eng','profile_target_applied_ai_track',55,TRUE),
    ('profile-title-rules-v2','2026-06-27-draft-2','target','candidate_profile_track: marketing automation','marketing automation','(^|[^a-z])(marketing automation engineer|marketing automation|technical marketing)([^a-z]|$)','candidate_profile.tracks.mkt_automation','profile_target_marketing_automation_track',70,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE OR REPLACE FUNCTION jobpush.profile_title_rule_decision(p_title TEXT)
RETURNS TABLE(classification_status TEXT, canonical_role TEXT, decision_reason TEXT)
LANGUAGE sql
STABLE
AS $$
    WITH title AS (
        SELECT lower(coalesce(p_title, '')) AS value
    ), language_signal AS (
        SELECT 1 AS hit
        FROM title
        WHERE value ~ '([ぁ-ゟァ-ヿ가-힣]|日本語|韓国|한국|서울)'
        LIMIT 1
    ), first_non_target AS (
        SELECT term.canonical_role, term.decision_reason
        FROM title
        JOIN jobpush.profile_title_rule_terms term
          ON term.active
         AND term.rule_version = 'profile-title-rules-v2'
         AND term.rule_type = 'non_target'
         AND title.value ~ term.regex_pattern
        ORDER BY term.priority, length(term.term) DESC, term.term
        LIMIT 1
    ), first_target AS (
        SELECT term.canonical_role, term.decision_reason
        FROM title
        JOIN jobpush.profile_title_rule_terms term
          ON term.active
         AND term.rule_version = 'profile-title-rules-v2'
         AND term.rule_type = 'target'
         AND title.value ~ term.regex_pattern
        ORDER BY term.priority, length(term.term) DESC, term.term
        LIMIT 1
    )
    SELECT
        CASE
            WHEN EXISTS (SELECT 1 FROM language_signal) THEN 'non_target'
            WHEN EXISTS (SELECT 1 FROM first_non_target) THEN 'non_target'
            WHEN EXISTS (SELECT 1 FROM first_target) THEN 'target'
            ELSE 'review'
        END AS classification_status,
        CASE
            WHEN EXISTS (SELECT 1 FROM first_target) AND NOT EXISTS (SELECT 1 FROM language_signal) AND NOT EXISTS (SELECT 1 FROM first_non_target)
                THEN (SELECT canonical_role FROM first_target)
            ELSE NULL
        END AS canonical_role,
        CASE
            WHEN EXISTS (SELECT 1 FROM language_signal) THEN 'profile_non_us_language_signal'
            WHEN EXISTS (SELECT 1 FROM first_non_target) THEN (SELECT decision_reason FROM first_non_target)
            WHEN EXISTS (SELECT 1 FROM first_target) THEN (SELECT decision_reason FROM first_target)
            ELSE 'profile_no_rule_match'
        END AS decision_reason;
$$;

CREATE TEMP TABLE profile_yaml_updates ON COMMIT DROP AS
WITH proposed AS (
    SELECT label.normalized_title,
           label.classification_status AS previous_status,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status IN ('target', 'non_target')
      AND (
          label.classification_status IS DISTINCT FROM decision.classification_status
          OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
          OR label.canonical_role IS DISTINCT FROM decision.canonical_role
          OR label.decision_reason IS DISTINCT FROM decision.decision_reason || ': candidate_profile 2026-06-29'
      )
)
SELECT * FROM proposed;

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-06-29',
       'system:profile-title-rules-v2'
FROM profile_yaml_updates;

UPDATE jobpush.job_title_labels label
SET classification_status = update_plan.new_status,
    canonical_role = update_plan.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = update_plan.decision_reason || ': candidate_profile 2026-06-29',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM profile_yaml_updates update_plan
WHERE label.normalized_title = update_plan.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM profile_yaml_updates update_plan
WHERE ml.normalized_title = update_plan.normalized_title;

COMMIT;

SELECT classification_status, rule_version, decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE '%candidate_profile 2026-06-29'
GROUP BY 1, 2, 3
ORDER BY titles DESC;
