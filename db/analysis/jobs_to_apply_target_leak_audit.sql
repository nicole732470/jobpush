\pset pager off

SELECT label.classification_status, label.rule_version, label.decision_reason,
       posting.normalized_title, count(*) AS active_jobs
FROM jobpush.job_postings_us posting
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE posting.active
  AND label.classification_status = 'target'
  AND lower(posting.normalized_title) ~ '(^engineer$|(^|[^a-z])(ios (software )?(engineer|developer)|android (software )?(engineer|developer)|mobile (software )?(engineer|developer)|administrative assistant|admin assistant|project manager|program manager|project management|program management|it operations management|cyber[ -]?security engineer)([^a-z]|$))'
GROUP BY 1,2,3,4
ORDER BY active_jobs DESC, posting.normalized_title;
