\pset pager off

BEGIN;

WITH proposed AS (
    SELECT label.normalized_title,
           label.classification_status AS previous_status,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE label.classification_status = 'review'
      AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status = 'non_target'
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': backfill_current_non_target_rules_2026-06-28',
       'system:profile-title-rules-v2'
FROM proposed;

WITH proposed AS (
    SELECT label.normalized_title,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE label.classification_status = 'review'
      AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status = 'non_target'
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = proposed.decision_reason || ': backfill_current_non_target_rules_2026-06-28',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM proposed
WHERE label.normalized_title = proposed.normalized_title;

COMMIT;

SELECT classification_status, rule_version, count(*) AS titles
FROM jobpush.job_title_labels
GROUP BY 1, 2
ORDER BY 1, 2;
