BEGIN;

-- Follow-up to migration 089:
-- Nicole found that title review still showed "cleaning"/"cleanroom"/
-- "sanitation" titles. Migration 089 blocked "cleaner" but not these common
-- variants, so they still reached human review.

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-9',
        'non_target',
        NULL,
        'cleaning sanitation cleanroom operations',
        '(^|[^a-z])(cleaning|cleaning associate|store cleaning|cleanroom|cleanline|clean up|clean processor|clean team|parts clean and prep|chemical clean technician|laboratory cleaning|sanitation|sanitation labor|sanitation manager|sanitation specialist|sanitation tech|sanitation technician)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_cleaning_leak',
        'profile_avoid_cleaning_sanitation_roles',
        18,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-9',
        'non_target',
        NULL,
        'taiwan cleanroom market markers',
        '(^|[^a-z])(taichung|tongluo)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_cleaning_leak',
        'profile_non_us_taiwan_market_marker',
        12,
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
    SELECT
        label.normalized_title,
        label.classification_status AS previous_status,
        'non_target'::text AS new_status,
        NULL::text AS canonical_role,
        CASE
            WHEN label.normalized_title ~* '(^|[^a-z])(taichung|tongluo)([^a-z]|$)'
                THEN 'profile_non_us_taiwan_market_marker'
            ELSE 'profile_avoid_cleaning_sanitation_roles'
        END AS decision_reason
    FROM jobpush.job_title_labels label
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND (
          label.normalized_title ~* '(^|[^a-z])(cleaning|cleaning associate|store cleaning|cleanroom|cleanline|clean up|clean processor|clean team|parts clean and prep|chemical clean technician|laboratory cleaning|sanitation|sanitation labor|sanitation manager|sanitation specialist|sanitation tech|sanitation technician)([^a-z]|$)'
          OR label.normalized_title ~* '(^|[^a-z])(taichung|tongluo)([^a-z]|$)'
      )
      AND (label.classification_status IS DISTINCT FROM 'non_target'
           OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
           OR label.canonical_role IS NOT NULL
           OR label.decision_reason NOT IN (
               'profile_avoid_cleaning_sanitation_roles: candidate_profile 2026-06-28',
               'profile_non_us_taiwan_market_marker: candidate_profile 2026-06-28'
           ))
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-06-28',
       'system:profile-title-rules-v2'
FROM proposed;

WITH proposed AS (
    SELECT
        label.normalized_title,
        'non_target'::text AS new_status,
        NULL::text AS canonical_role,
        CASE
            WHEN label.normalized_title ~* '(^|[^a-z])(taichung|tongluo)([^a-z]|$)'
                THEN 'profile_non_us_taiwan_market_marker'
            ELSE 'profile_avoid_cleaning_sanitation_roles'
        END AS decision_reason
    FROM jobpush.job_title_labels label
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND (
          label.normalized_title ~* '(^|[^a-z])(cleaning|cleaning associate|store cleaning|cleanroom|cleanline|clean up|clean processor|clean team|parts clean and prep|chemical clean technician|laboratory cleaning|sanitation|sanitation labor|sanitation manager|sanitation specialist|sanitation tech|sanitation technician)([^a-z]|$)'
          OR label.normalized_title ~* '(^|[^a-z])(taichung|tongluo)([^a-z]|$)'
      )
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = proposed.decision_reason || ': candidate_profile 2026-06-28',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM proposed
WHERE label.normalized_title = proposed.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

UPDATE jobpush.job_title_ml_classifications prediction
SET applied = FALSE
FROM jobpush.job_title_labels label
WHERE prediction.normalized_title = label.normalized_title
  AND label.classification_status = 'non_target'
  AND (
      label.decision_reason LIKE 'profile_avoid_cleaning_sanitation_roles%%'
      OR label.decision_reason LIKE 'profile_non_us_taiwan_market_marker%%'
  );

COMMIT;

SELECT classification_status, rule_version, decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_cleaning_sanitation_roles%%'
   OR decision_reason LIKE 'profile_non_us_taiwan_market_marker%%'
GROUP BY 1, 2, 3
ORDER BY titles DESC;
