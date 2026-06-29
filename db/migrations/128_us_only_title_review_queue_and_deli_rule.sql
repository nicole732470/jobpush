BEGIN;

CREATE OR REPLACE VIEW jobpush.job_title_review_queue AS
WITH us_catalog AS (
    SELECT
        posting.normalized_title,
        min(posting.title) AS example_title,
        count(*) AS active_posting_count,
        count(DISTINCT posting.consolidation_key) AS company_count
    FROM jobpush.job_postings_us posting
    GROUP BY posting.normalized_title
), mapping_resolution AS (
    SELECT
        lower(btrim(mapping.normalized_job_title)) AS normalized_title,
        count(DISTINCT mapping.normalized_soc_code) AS matched_soc_count,
        count(DISTINCT mapping.normalized_soc_code)
            FILTER (WHERE target.normalized_soc_code IS NOT NULL) AS target_soc_count,
        count(DISTINCT mapping.normalized_soc_code)
            FILTER (WHERE target.normalized_soc_code IS NULL) AS non_target_soc_count,
        string_agg(DISTINCT mapping.normalized_soc_code, ', ' ORDER BY mapping.normalized_soc_code) AS matched_soc_codes,
        string_agg(DISTINCT mapping.soc_title, ' | ' ORDER BY mapping.soc_title) AS matched_soc_titles,
        string_agg(DISTINCT target.representative_title, ' | ' ORDER BY target.representative_title)
            FILTER (WHERE target.normalized_soc_code IS NOT NULL) AS target_soc_titles
    FROM jobpush.soc_role_title_mappings mapping
    LEFT JOIN jobpush.target_soc_roles target
      ON target.normalized_soc_code = mapping.normalized_soc_code
     AND target.active
    GROUP BY lower(btrim(mapping.normalized_job_title))
), candidate AS (
    SELECT
        us_catalog.normalized_title,
        us_catalog.example_title,
        us_catalog.active_posting_count,
        us_catalog.company_count,
        mapping.matched_soc_count,
        mapping.target_soc_count,
        mapping.non_target_soc_count,
        mapping.matched_soc_codes,
        mapping.matched_soc_titles,
        mapping.target_soc_titles,
        CASE
          WHEN mapping.normalized_title IS NULL THEN 'review'
          WHEN mapping.target_soc_count > 0 AND mapping.non_target_soc_count = 0 THEN 'target'
          WHEN mapping.target_soc_count = 0 AND mapping.non_target_soc_count > 0 THEN 'non_target'
          ELSE 'review'
        END AS suggested_status,
        CASE
          WHEN mapping.normalized_title IS NULL THEN 'no_exact_raw_title_match'
          WHEN mapping.target_soc_count > 0 AND mapping.non_target_soc_count = 0 THEN 'exact_target_soc_only'
          WHEN mapping.target_soc_count = 0 AND mapping.non_target_soc_count > 0 THEN 'exact_non_target_soc_only'
          ELSE 'mixed_soc_conflict'
        END AS suggestion_reason
    FROM us_catalog
    LEFT JOIN mapping_resolution mapping USING (normalized_title)
)
SELECT
    candidate.normalized_title,
    candidate.example_title,
    candidate.active_posting_count,
    candidate.company_count,
    candidate.suggested_status,
    candidate.suggestion_reason,
    candidate.matched_soc_codes,
    candidate.matched_soc_titles,
    label.classification_status,
    label.canonical_role,
    label.decision_reason,
    label.labeled_by,
    label.updated_at
FROM candidate
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE label.classification_status = 'review'
ORDER BY candidate.active_posting_count DESC, candidate.company_count DESC,
         candidate.normalized_title;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES (
    'profile-title-rules-v2',
    '2026-06-29-draft-8',
    'non_target',
    NULL,
    'deli grocery food service assistant manager',
    '(^|[^a-z])(deli|food service|foodservice|grocery assistant manager|deli assistant manager|bakery assistant manager|restaurant assistant manager)([^a-z]|$)',
    'nicole_review_observation_2026-06-29_title_queue',
    'profile_avoid_food_service_store_management',
    20,
    TRUE
)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

WITH proposed AS (
    SELECT label.normalized_title,
           label.classification_status AS previous_status,
           'non_target'::text AS new_status,
           NULL::text AS canonical_role,
           'profile_avoid_food_service_store_management'::text AS decision_reason
    FROM jobpush.job_title_labels label
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND lower(label.normalized_title) ~ '(^|[^a-z])(deli|food service|foodservice|grocery assistant manager|deli assistant manager|bakery assistant manager|restaurant assistant manager)([^a-z]|$)'
      AND (label.classification_status IS DISTINCT FROM 'non_target'
           OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
           OR label.canonical_role IS NOT NULL
           OR label.decision_reason IS DISTINCT FROM 'profile_avoid_food_service_store_management: candidate_profile 2026-06-29')
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-06-29',
       'system:profile-title-rules-v2'
FROM proposed;

WITH proposed AS (
    SELECT label.normalized_title,
           'non_target'::text AS new_status,
           NULL::text AS canonical_role,
           'profile_avoid_food_service_store_management'::text AS decision_reason
    FROM jobpush.job_title_labels label
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND lower(label.normalized_title) ~ '(^|[^a-z])(deli|food service|foodservice|grocery assistant manager|deli assistant manager|bakery assistant manager|restaurant assistant manager)([^a-z]|$)'
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = proposed.decision_reason || ': candidate_profile 2026-06-29',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM proposed
WHERE label.normalized_title = proposed.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
WHERE lower(ml.normalized_title) ~ '(^|[^a-z])(deli|food service|foodservice|grocery assistant manager|deli assistant manager|bakery assistant manager|restaurant assistant manager)([^a-z]|$)';

COMMIT;

SELECT 'deli_still_in_review_queue' AS check_name, count(*) AS rows
FROM jobpush.job_title_review_queue
WHERE normalized_title = 'deli assistant manager';

SELECT normalized_title, classification_status, decision_reason
FROM jobpush.job_title_labels
WHERE normalized_title IN ('data center engineer', 'deli assistant manager')
ORDER BY normalized_title;
