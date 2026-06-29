\pset pager off

\echo '=== new rule terms ==='
SELECT rule_type, term, decision_reason, active
FROM jobpush.profile_title_rule_terms
WHERE profile_version = '2026-06-27-draft-2'
  AND source LIKE 'candidate_profile.%'
ORDER BY rule_type, priority, term;

\echo '=== labels hit by new decision reasons ==='
SELECT classification_status, rule_version, decision_reason, COUNT(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_required_non_english_non_chinese_language%'
   OR decision_reason LIKE 'profile_avoid_pure_non_python_sde%'
   OR decision_reason LIKE 'profile_target_marketing_automation_track%'
   OR decision_reason LIKE 'profile_target_applied_ai_track%'
   OR decision_reason LIKE 'profile_target_solutions_track%'
   OR decision_reason LIKE 'profile_target_product_track%'
GROUP BY 1, 2, 3
ORDER BY titles DESC;

\echo '=== sampled language exclusions ==='
SELECT normalized_title, classification_status, decision_reason
FROM jobpush.job_title_labels
WHERE decision_reason LIKE 'profile_avoid_required_non_english_non_chinese_language%'
ORDER BY normalized_title
LIMIT 30;
