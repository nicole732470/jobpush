\pset pager off

SELECT
    label.normalized_title,
    label.classification_status,
    label.rule_version,
    label.decision_reason,
    count(posting.*) FILTER (WHERE posting.active) AS active_jobs,
    min(posting.title) AS example_title
FROM jobpush.job_title_labels label
LEFT JOIN jobpush.job_postings posting USING (normalized_title)
WHERE label.normalized_title ~ '(^|[^a-z])(c software engineer|c developer|c programmer|c\\+\\+|c#)([^a-z]|$)'
   OR posting.title ~* '(^|[^a-z])(c\\+\\+|c#)([^a-z]|$)'
GROUP BY 1, 2, 3, 4
ORDER BY active_jobs DESC NULLS LAST, label.normalized_title;
