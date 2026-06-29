\pset pager off

\echo '=== Current title label distribution ==='
SELECT classification_status,
       COALESCE(rule_version, '<blank>') AS rule_version,
       count(*) AS distinct_titles
FROM jobpush.job_title_labels
GROUP BY 1, 2
ORDER BY 1, distinct_titles DESC;

\echo '=== High-volume unresolved review titles ==='
SELECT label.normalized_title,
       COALESCE(catalog.active_posting_count, 0) AS active_postings,
       COALESCE(catalog.company_count, 0) AS companies
FROM jobpush.job_title_labels label
LEFT JOIN jobpush.job_title_catalog catalog USING (normalized_title)
WHERE label.classification_status = 'review'
ORDER BY COALESCE(catalog.active_posting_count, 0) DESC, label.normalized_title
LIMIT 80;

\echo '=== Obvious remaining noise families in review ==='
WITH review AS (
    SELECT label.normalized_title, COALESCE(catalog.active_posting_count, 0) AS active_postings
    FROM jobpush.job_title_labels label
    LEFT JOIN jobpush.job_title_catalog catalog USING (normalized_title)
    WHERE label.classification_status = 'review'
), classified AS (
    SELECT CASE
        WHEN normalized_title ~* '(^|[^a-z])(driver|cleaner|front desk|restaurant|warehouse|security guard|nurse|plumber|teacher)([^a-z]|$)' THEN 'known hard avoid leak'
        WHEN normalized_title ~* '(^|[^a-z])(manager|supervisor|director|principal|lead|head|vp|vice president)([^a-z]|$)' THEN 'seniority/management boundary'
        WHEN normalized_title ~* '(^|[^a-z])(architect|consulting|consultant|partner|relationship manager|sales|customer|client)([^a-z]|$)' THEN 'business/client/consulting boundary'
        WHEN normalized_title ~* '(^|[^a-z])(engineer|developer|data|product|analyst|program|project|technical|cloud|ai|machine learning|devops|qa)([^a-z]|$)' THEN 'possible target-like technical'
        ELSE 'other review'
    END AS family,
    active_postings
    FROM review
)
SELECT family,
       count(*) AS distinct_titles,
       sum(active_postings) AS active_postings
FROM classified
GROUP BY 1
ORDER BY active_postings DESC NULLS LAST, distinct_titles DESC;
