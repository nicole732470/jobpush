\pset pager off

\echo '=== Site review rows where candidate 1 came from ats_url_guess ==='
SELECT
    count(*) AS rows_with_ats_guess_candidate_1,
    count(*) FILTER (
        WHERE workbench.candidate_2_site_id IS NOT NULL
           OR workbench.candidate_3_site_id IS NOT NULL
    ) AS rows_still_showing_extra_candidates
FROM jobpush.career_site_review_workbench workbench
JOIN jobpush.career_sites site
  ON site.site_id = workbench.candidate_1_site_id
WHERE workbench.action_status = 'REVIEW_CANDIDATES'
  AND site.discovery_source = 'ats_url_guess';

\echo '=== Sample ats_url_guess rows in site review ==='
SELECT
    workbench.priority_tier,
    workbench.priority_score,
    workbench.canonical_name,
    workbench.candidate_count,
    workbench.candidate_1_source,
    workbench.candidate_1_url,
    workbench.candidate_2_url,
    workbench.candidate_3_url
FROM jobpush.career_site_review_workbench workbench
JOIN jobpush.career_sites site
  ON site.site_id = workbench.candidate_1_site_id
WHERE workbench.action_status = 'REVIEW_CANDIDATES'
  AND site.discovery_source = 'ats_url_guess'
ORDER BY workbench.priority_tier, workbench.priority_score DESC NULLS LAST, workbench.canonical_name
LIMIT 20;
