\pset pager off

BEGIN;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES (
    'profile-title-rules-v2','2026-07-13-draft-8','non_target',NULL,
    'pure marketing role combinations',
    '(^|[^a-z])((social media) (manager|specialist|coordinator|strategist|producer)|(digital|content|brand|field|growth|performance|email|product) marketing( (manager|specialist|coordinator|associate|assistant|analyst|director|representative|consultant|strategist))?|marketing (specialist|coordinator|manager|associate|assistant|analyst|director|representative|consultant|strategist))([^a-z]|$)',
    'candidate_profile.avoid_tracks.pure_marketing',
    'profile_avoid_pure_marketing_roles',6,TRUE
)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE pure_marketing_exclusions ON COMMIT DROP AS
SELECT normalized_title, classification_status AS previous_status
FROM jobpush.job_title_labels
WHERE lower(normalized_title) ~ '(^|[^a-z])((social media) (manager|specialist|coordinator|strategist|producer)|(digital|content|brand|field|growth|performance|email|product) marketing( (manager|specialist|coordinator|associate|assistant|analyst|director|representative|consultant|strategist))?|marketing (specialist|coordinator|manager|associate|assistant|analyst|director|representative|consultant|strategist))([^a-z]|$)'
  AND lower(normalized_title) !~ '(marketing automation|technical marketing)';

INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, 'non_target', NULL,
       'profile_avoid_pure_marketing_roles: candidate_profile 2026-07-13-draft-8',
       'nicole'
FROM pure_marketing_exclusions
WHERE previous_status IS DISTINCT FROM 'non_target';

UPDATE jobpush.job_title_labels label
SET classification_status = 'non_target',
    canonical_role = NULL,
    rule_version = 'profile-title-rules-v2',
    decision_reason = 'profile_avoid_pure_marketing_roles: candidate_profile 2026-07-13-draft-8',
    labeled_by = 'nicole',
    labeled_at = now(),
    updated_at = now()
FROM pure_marketing_exclusions exclusion
WHERE label.normalized_title = exclusion.normalized_title;

UPDATE jobpush.job_title_ml_classifications ml
SET applied = FALSE
FROM pure_marketing_exclusions exclusion
WHERE ml.normalized_title = exclusion.normalized_title;

COMMIT;

SELECT classification_status, count(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason = 'profile_avoid_pure_marketing_roles: candidate_profile 2026-07-13-draft-8'
GROUP BY 1;
