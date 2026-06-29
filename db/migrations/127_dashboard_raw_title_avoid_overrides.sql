BEGIN;

-- Raw title escapes the normalized-title label when normalization drops tokens
-- such as "C++" and turns "C++ Software Engineer" into generic "software engineer".
-- ponytail: final dashboard guard only; a richer job-level classifier can replace
-- this when raw-title labels exist.
CREATE OR REPLACE VIEW jobpush.dashboard_jobs AS
SELECT
    posting.site_id,
    posting.external_job_id,
    posting.consolidation_key,
    target.canonical_name,
    target.priority_tier,
    posting.title,
    posting.normalized_title,
    posting.location,
    posting.category,
    posting.employment_type,
    CASE
        WHEN (
            (
                posting.title ILIKE '%%c++%%'
                OR posting.title ILIKE '%%c#%%'
                OR posting.title ILIKE '%%.net/c#%%'
                OR posting.title ILIKE '%%c#/.net%%'
            )
            AND (
                posting.title ILIKE '%%software%%'
                OR posting.title ILIKE '%%developer%%'
                OR posting.title ILIKE '%%engineer%%'
                OR posting.title ILIKE '%%full stack%%'
                OR posting.title ILIKE '%%full-stack%%'
                OR posting.title ILIKE '%%backend%%'
                OR posting.title ILIKE '%%frontend%%'
                OR posting.title ILIKE '%%sdet%%'
            )
        )
        OR posting.title ~* '(^|[^a-z0-9])c (software engineer|developer|programmer)([^a-z0-9]|$)'
            THEN 'non_target'
        ELSE COALESCE(label.classification_status, 'review')
    END AS role_status,
    CASE
        WHEN (
            (
                posting.title ILIKE '%%c++%%'
                OR posting.title ILIKE '%%c#%%'
                OR posting.title ILIKE '%%.net/c#%%'
                OR posting.title ILIKE '%%c#/.net%%'
            )
            AND (
                posting.title ILIKE '%%software%%'
                OR posting.title ILIKE '%%developer%%'
                OR posting.title ILIKE '%%engineer%%'
                OR posting.title ILIKE '%%full stack%%'
                OR posting.title ILIKE '%%full-stack%%'
                OR posting.title ILIKE '%%backend%%'
                OR posting.title ILIKE '%%frontend%%'
                OR posting.title ILIKE '%%sdet%%'
            )
        )
        OR posting.title ~* '(^|[^a-z0-9])c (software engineer|developer|programmer)([^a-z0-9]|$)'
            THEN NULL
        ELSE label.canonical_role
    END AS canonical_role,
    COALESCE(action.action_status, 'new') AS application_status,
    action.notes AS application_notes,
    posting.posted_text,
    posting.first_seen_at,
    posting.last_seen_at,
    posting.job_url
FROM jobpush.job_postings_us posting
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
LEFT JOIN jobpush.job_application_actions action
  ON action.site_id = posting.site_id
 AND action.external_job_id = posting.external_job_id;

COMMIT;

SELECT role_status, count(*) AS jobs
FROM jobpush.dashboard_jobs
WHERE title ILIKE '%%c++%%'
   OR title ILIKE '%%c#%%'
   OR title ILIKE '%%.net/c#%%'
   OR title ILIKE '%%c#/.net%%'
   OR title ~* '(^|[^a-z0-9])c (software engineer|developer|programmer)([^a-z0-9]|$)'
GROUP BY role_status
ORDER BY jobs DESC;
