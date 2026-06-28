\pset pager off

\echo '=== ats_url_guess source distribution ==='
SELECT source_type, verification_status, count(*) AS sites, count(DISTINCT consolidation_key) AS companies
FROM jobpush.career_sites
WHERE discovery_source = 'ats_url_guess'
GROUP BY 1, 2
ORDER BY sites DESC, source_type, verification_status;

\echo '=== ats_url_guess sample ==='
SELECT
    target.canonical_name,
    site.source_type,
    site.source_key,
    site.candidate_rank,
    site.candidate_score,
    left(site.evidence_title, 120) AS evidence_title,
    site.site_url
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.discovery_source = 'ats_url_guess'
ORDER BY site.source_type, target.priority_score DESC NULLS LAST, target.canonical_name
LIMIT 80;

\echo '=== smartrecruiters suspicious evidence ==='
SELECT
    left(site.evidence_title, 120) AS evidence_title,
    count(*) AS sites
FROM jobpush.career_sites site
WHERE site.discovery_source = 'ats_url_guess'
  AND site.source_type = 'smartrecruiters'
GROUP BY 1
ORDER BY sites DESC, evidence_title
LIMIT 40;
