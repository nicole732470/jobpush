BEGIN;

-- A bare "consultant" has no reliable career meaning. Keep only contextual
-- multi-word consultant titles eligible for automatic target classification.
UPDATE jobpush.profile_title_rule_terms
SET active = FALSE
WHERE rule_version = 'profile-title-rules-v2'
  AND decision_reason = 'profile_target_analyst_marketing_track';

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2','2026-07-31-current-intent','target','candidate_profile_track: analyst/bi',
     'analyst/bi and contextual consultant','(^|[^a-z])(data analyst|business analyst|business intelligence|bi analyst|bi engineer|systems analyst|technical consultant|solutions? consultant|implementation consultant|business consultant)([^a-z]|$)',
     'candidate_profile.tracks.business_analyst','profile_target_contextual_consultant',70,TRUE),
    ('profile-title-rules-v2','2026-07-31-current-intent','non_target',NULL,
     'clinical care roles','(^|[^a-z])(lactation consultant|registered nurse|rn[- ]|physician|clinical nurse|patient care)([^a-z]|$)',
     'candidate_profile.avoid_tracks','profile_avoid_clinical_care_roles',5,TRUE),
    ('profile-title-rules-v2','2026-07-31-current-intent','non_target',NULL,
     'pure sales management','(^|[^a-z])(sales manager|sales development representative|sales operations manager|relationship manager)([^a-z]|$)',
     'candidate_profile.avoid_tracks.pure_sales','profile_avoid_pure_sales_roles',5,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

SELECT * FROM jobpush.reapply_latest_profile_title_rules();

-- Current explicit excludes supersede older manual target labels, while all
-- other manual reviews keep their original authority.
WITH decisions AS (
    SELECT label.normalized_title, decision.canonical_role, decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE label.classification_status = 'target'
      AND COALESCE(label.rule_version, '') LIKE 'manual%'
      AND decision.classification_status = 'non_target'
)
UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'profile-title-rules-v2',
    decision_reason = decisions.decision_reason || ': supersedes older manual target',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM decisions
WHERE label.normalized_title = decisions.normalized_title;

COMMIT;
