\echo '=== Remaining queue: rank-1 source type ==='
SELECT
    COALESCE(c1.source_type, '(no rank-1 unverified)') AS candidate_1_source,
    COUNT(*) AS companies
FROM jobpush.career_site_company_review_queue q
LEFT JOIN jobpush.career_sites c1
  ON c1.site_id = q.candidate_1_site_id
GROUP BY 1
ORDER BY companies DESC;

\echo '=== Easy wins: rank-1 is known ATS (greenhouse/workday/lever/etc) ==='
SELECT q.consolidation_key, q.canonical_name, q.candidate_1_site_id, q.candidate_1_url, q.candidate_1_source
FROM jobpush.career_site_company_review_queue q
WHERE q.candidate_1_source IN ('greenhouse', 'workday', 'lever', 'ashby', 'smartrecruiters', 'icims', 'oracle_cloud')
ORDER BY q.priority_score DESC NULLS LAST, q.canonical_name
LIMIT 40;
