BEGIN;

-- Nicole title-review issue, 2026-06-28:
-- After P1 crawl expansion, several large career sites introduced high-volume
-- obvious non-target titles into job_title_review_queue: cleaner/janitorial,
-- merchant/merchandising, Leader/Leadership seniority titles, and non-US market
-- markers such as M/F/D, H/F, EMEA, LATAM, Japan, Thailand, ANZ.
-- These should be deterministic non-target labels, not human-review work.

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-7',
        'non_target',
        NULL,
        'leader leadership seniority',
        '(^|[^a-z])(leader|leadership)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_p1_expansion',
        'profile_hard_seniority_leader_exclusion',
        10,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-7',
        'non_target',
        NULL,
        'cleaner janitorial housekeeping',
        '(^|[^a-z])(cleaner|janitor|janitorial|custodian|custodial|housekeeper|housekeeping|sanitation worker|environmental services aide)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_p1_expansion',
        'profile_avoid_cleaner_janitorial_roles',
        18,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-7',
        'non_target',
        NULL,
        'merchant merchandising retail buying',
        '(^|[^a-z])(merchant|associate merchant|digital merchant|site merchant|merchandising|merchandiser|merchandise coordinator|merchandise planner)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_p1_expansion',
        'profile_avoid_merchant_merchandising_roles',
        18,
        TRUE
    ),
    (
        'profile-title-rules-v2',
        '2026-06-28-draft-7',
        'non_target',
        NULL,
        'non us market language markers',
        '(^|[^a-z])(m/f/d|f/m/d|m/f/x|h/f|cdi|cdd|emea|latam|apac|anz|japan|thailand|port klang|cork|france|germany|deutschland|poland|polish|italy|spain|singapore|hong kong|tokyo|osaka)([^a-z]|$)',
        'nicole_review_observation_2026-06-28_p1_expansion',
        'profile_non_us_market_or_language_marker',
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
          'profile_hard_seniority_leader_exclusion',
          'profile_avoid_cleaner_janitorial_roles',
          'profile_avoid_merchant_merchandising_roles',
          'profile_non_us_market_or_language_marker'
      )
      AND (label.classification_status IS DISTINCT FROM 'non_target'
           OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
           OR label.canonical_role IS NOT NULL
           OR label.decision_reason IS DISTINCT FROM decision.decision_reason || ': candidate_profile 2026-06-28')
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
    SELECT label.normalized_title,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status = 'non_target'
      AND decision.decision_reason IN (
          'profile_hard_seniority_leader_exclusion',
          'profile_avoid_cleaner_janitorial_roles',
          'profile_avoid_merchant_merchandising_roles',
          'profile_non_us_market_or_language_marker'
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

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
WHERE lower(ml.normalized_title) ~ '(^|[^a-z])(leader|leadership|cleaner|janitor|janitorial|custodian|housekeeper|housekeeping|merchant|merchandising|merchandiser|m/f/d|f/m/d|m/f/x|h/f|cdi|cdd|emea|latam|apac|anz|japan|thailand|port klang|cork|france|germany|deutschland|poland|polish|italy|spain|singapore|hong kong|tokyo|osaka)([^a-z]|$)';

COMMIT;

SELECT classification_status, rule_version, decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_hard_seniority_leader_exclusion%%'
   OR decision_reason LIKE 'profile_avoid_cleaner_janitorial_roles%%'
   OR decision_reason LIKE 'profile_avoid_merchant_merchandising_roles%%'
   OR decision_reason LIKE 'profile_non_us_market_or_language_marker%%'
GROUP BY 1, 2, 3
ORDER BY titles DESC;
