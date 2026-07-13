\pset pager off
\echo '=== Past generic-html-ats-link-resolver runs ==='
SELECT left(run_id,40) AS run_id, target_count, candidate_count, error_count,
       CASE WHEN target_count>0 THEN round(100.0*candidate_count/target_count,1) ELSE 0 END AS candidates_per_100_targets,
       status, started_at
FROM jobpush.career_site_discovery_runs
WHERE cohort = 'generic-html-ats-link-resolver'
ORDER BY started_at DESC
LIMIT 15;

\echo '=== Candidates from resolver by source_type / verification ==='
SELECT site.source_type, site.verification_status,
       count(*) AS sites,
       count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
WHERE site.discovery_source = 'generic_html_link_resolver'
GROUP BY 1,2
ORDER BY companies DESC, 1,2;

\echo '=== Enabled companies from resolver findings ==='
SELECT target.priority_tier, count(DISTINCT site.consolidation_key) AS enabled_companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.discovery_source = 'generic_html_link_resolver'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
GROUP BY 1
ORDER BY 1;
