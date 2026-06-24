-- TablePlus-friendly networking queries. Change only the value in each
-- params CTE; no psql variables are required.

-- 1) Find the exact company key first. This prevents similarly named
-- employers from being mixed together.
WITH params AS (
    SELECT 'PFIZER'::text AS company_name
)
SELECT
    company.consolidation_key,
    company.canonical_name,
    company.employer_city,
    company.employer_state,
    target.priority_tier,
    target.priority_source,
    count(posting.external_job_id) AS active_us_jobs
FROM params
JOIN jobpush.company_targets_consolidated company
  ON company.canonical_name ILIKE '%' || params.company_name || '%'
LEFT JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN jobpush.job_postings_us posting USING (consolidation_key)
GROUP BY company.consolidation_key, company.canonical_name,
         company.employer_city, company.employer_state,
         target.priority_tier, target.priority_source
ORDER BY active_us_jobs DESC, company.canonical_name;

-- 2) Paste the chosen consolidation_key below to see every currently active
-- US role, including its target/review/non-target decision and direct URL.
WITH params AS (
    SELECT '13-5315170'::text AS company_key
)
SELECT
    target.canonical_name,
    target.priority_tier,
    posting.title,
    posting.location,
    posting.category,
    posting.employment_type,
    COALESCE(label.classification_status, 'review') AS role_status,
    label.canonical_role,
    posting.posted_text,
    posting.first_seen_at,
    posting.last_seen_at,
    posting.job_url
FROM params
JOIN jobpush.crawl_targets target
  ON target.consolidation_key = params.company_key
JOIN jobpush.job_postings_us posting
  ON posting.consolidation_key = target.consolidation_key
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
ORDER BY
    CASE COALESCE(label.classification_status, 'review')
        WHEN 'target' THEN 0 WHEN 'review' THEN 1 ELSE 2
    END,
    posting.title,
    posting.location;

-- 3) Networking summary: which role families and locations are hiring most?
WITH params AS (
    SELECT '13-5315170'::text AS company_key
)
SELECT
    COALESCE(label.classification_status, 'review') AS role_status,
    COALESCE(label.canonical_role, posting.category, posting.normalized_title) AS role_family,
    posting.location,
    count(*) AS active_us_jobs,
    min(posting.title) AS example_title
FROM params
JOIN jobpush.job_postings_us posting
  ON posting.consolidation_key = params.company_key
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
GROUP BY COALESCE(label.classification_status, 'review'),
         COALESCE(label.canonical_role, posting.category, posting.normalized_title),
         posting.location
ORDER BY active_us_jobs DESC, role_status, role_family, posting.location;

-- To hide roles already confirmed irrelevant, add this before ORDER BY in
-- query 2, or before GROUP BY in query 3:
-- WHERE COALESCE(label.classification_status, 'review') <> 'non_target'
