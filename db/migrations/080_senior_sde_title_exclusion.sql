BEGIN;

-- Nicole profile update, 2026-06-27:
-- Senior-level SDE / software-engineering track titles are not target roles.
-- This is intentionally conditional: "senior product manager" is not matched
-- by this rule unless it also contains a software/SDE-track term.
INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES (
    'profile-title-rules-v2',
    '2026-06-27-draft-2',
    'non_target',
    NULL,
    'senior sde/software engineering',
    '(^|[^a-z])((senior|sr\\.?)[^a-z0-9]+([a-z0-9+#./-]+[^a-z0-9]+){0,5}(sde|software engineer|software developer|software engineering|full[- ]stack|backend|front[- ]end|frontend|devops|cloud engineer|data engineer|qa engineer|test engineer|cybersecurity|security engineer)|((sde|software engineer|software developer|software engineering|full[- ]stack|backend|front[- ]end|frontend|devops|cloud engineer|data engineer|qa engineer|test engineer|cybersecurity|security engineer)[^a-z0-9]+([a-z0-9+#./-]+[^a-z0-9]+){0,5}(senior|sr\\.?)))([^a-z]|$)',
    'candidate_profile.tracks.sde_eng.seniority_policy updated 2026-06-27',
    'profile_avoid_senior_sde_track',
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
      AND decision.classification_status IN ('target', 'non_target')
      AND decision.decision_reason = 'profile_avoid_senior_sde_track'
      AND (label.classification_status IS DISTINCT FROM decision.classification_status
           OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
           OR label.canonical_role IS DISTINCT FROM decision.canonical_role
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
      AND decision.classification_status IN ('target', 'non_target')
      AND decision.decision_reason = 'profile_avoid_senior_sde_track'
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
