\set ON_ERROR_STOP on
\pset pager off

BEGIN;

SELECT jobpush.apply_manual_job_title_label(
    title, 'target', canonical_role,
    'Nicole new_grad_review.csv T label 2026-07-13', 'nicole'
)
FROM (VALUES
    ('new college grad - supply chain planner', 'candidate_profile_track: analyst/bi'),
    ('agriculture sales analyst - fall 2026 us graduate program', 'candidate_profile_track: analyst/bi'),
    ('deployment strategist new grad - intel us government', 'candidate_profile_track: applied_ai'),
    ('point72 academy investment analyst program for upcoming graduates 2027 us', 'candidate_profile_track: analyst/bi'),
    ('technical support engineer - university graduate 2026', 'candidate_profile_track: customer_success'),
    ('new college grad - supply management analyst', 'candidate_profile_track: analyst/bi')
) AS manual(title, canonical_role);

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2', '2026-07-13-draft-7', 'target',
     'candidate_profile_track: analyst/bi', 'supply chain planning',
     '(^|[^a-z])(supply chain planner|supply management analyst)([^a-z]|$)',
     'Nicole new_grad_review.csv T labels', 'profile_target_supply_chain_analysis', 45, TRUE),
    ('profile-title-rules-v2', '2026-07-13-draft-7', 'target',
     'candidate_profile_track: analyst/bi', 'agriculture sales analyst',
     '(^|[^a-z])agriculture sales analyst([^a-z]|$)',
     'Nicole new_grad_review.csv T labels', 'profile_target_agriculture_sales_analysis', 45, TRUE),
    ('profile-title-rules-v2', '2026-07-13-draft-7', 'target',
     'candidate_profile_track: applied_ai', 'deployment strategist',
     '(^|[^a-z])deployment strategist([^a-z]|$)',
     'Nicole new_grad_review.csv T labels', 'profile_target_deployment_strategy', 45, TRUE),
    ('profile-title-rules-v2', '2026-07-13-draft-7', 'target',
     'candidate_profile_track: analyst/bi', 'investment analyst',
     '(^|[^a-z])investment analyst([^a-z]|$)',
     'Nicole new_grad_review.csv T labels', 'profile_target_investment_analysis', 45, TRUE),
    ('profile-title-rules-v2', '2026-07-13-draft-7', 'target',
     'candidate_profile_track: customer_success', 'technical support engineer',
     '(^|[^a-z])technical support engineer([^a-z]|$)',
     'Nicole new_grad_review.csv T labels', 'profile_target_technical_support_engineering', 45, TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

CREATE TEMP TABLE generalized_review_targets ON COMMIT DROP AS
SELECT label.normalized_title
FROM jobpush.job_title_labels label
WHERE label.classification_status = 'review'
  AND label.normalized_title ~* '(^|[^a-z])(supply chain planner|supply management analyst|agriculture sales analyst|deployment strategist|investment analyst|technical support engineer)([^a-z]|$)';

UPDATE jobpush.job_title_labels label
SET classification_status = 'target',
    rule_version = 'profile-title-rules-v2',
    decision_reason = 'Nicole new_grad_review.csv generalized target 2026-07-13',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM generalized_review_targets target
WHERE label.normalized_title = target.normalized_title;

COMMIT;

SELECT classification_status, count(*) AS titles
FROM jobpush.job_title_labels
WHERE normalized_title ~* '(^|[^a-z])(supply chain planner|supply management analyst|agriculture sales analyst|deployment strategist|investment analyst|technical support engineer)([^a-z]|$)'
GROUP BY 1
ORDER BY 1;
