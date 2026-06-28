\pset pager off

SELECT
    q.normalized_title,
    q.example_title,
    q.active_posting_count,
    q.company_count,
    d.classification_status AS rule_status,
    d.decision_reason AS rule_reason
FROM jobpush.job_title_review_queue q
CROSS JOIN LATERAL jobpush.profile_title_rule_decision(q.normalized_title) d
WHERE q.normalized_title ~* 'clean|janitor|housekeep|custod|sanitation'
ORDER BY q.active_posting_count DESC, q.company_count DESC, q.normalized_title
LIMIT 100;
