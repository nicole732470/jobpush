\pset pager off

BEGIN;

UPDATE jobpush.profile_title_rule_terms
SET active = FALSE
WHERE decision_reason = 'profile_avoid_pure_marketing_roles';

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES (
    'profile-title-rules-v2','2026-07-13-draft-8','non_target',NULL,
    'pure marketing role combinations with technical exception',
    '(^|[^a-z])((social media) (manager|specialist|coordinator|strategist|producer)|(digital|content|brand|field|growth|performance|email|product) marketing( (manager|specialist|coordinator|associate|assistant|analyst|director|representative|consultant|strategist))?|(?<!technical )marketing (specialist|coordinator|manager|associate|assistant|analyst|director|representative|consultant|strategist))([^a-z]|$)',
    'candidate_profile.avoid_tracks.pure_marketing',
    'profile_avoid_pure_marketing_roles',6,TRUE
)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    active = TRUE,
    profile_version = EXCLUDED.profile_version;

COMMIT;

SELECT jobpush.profile_title_rule_decision('Marketing Specialist') AS pure_marketing,
       jobpush.profile_title_rule_decision('Social Media Manager') AS social_media,
       jobpush.profile_title_rule_decision('Technical Marketing Manager') AS technical_marketing,
       jobpush.profile_title_rule_decision('Marketing Automation Engineer') AS marketing_automation;
