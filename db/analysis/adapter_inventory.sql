\echo '=== Verified enabled sites by source type ==='
SELECT source_type, COUNT(*) AS sites, COUNT(DISTINCT consolidation_key) AS companies
FROM jobpush.career_sites
WHERE verification_status = 'verified' AND crawl_enabled
GROUP BY source_type
ORDER BY sites DESC, source_type;

\echo '=== Verified enabled site details ==='
SELECT ct.priority_tier, cs.consolidation_key, ct.canonical_name,
       cs.site_id, cs.source_type, cs.site_url, cs.crawl_status
FROM jobpush.career_sites cs
JOIN jobpush.crawl_targets ct USING (consolidation_key)
WHERE cs.verification_status = 'verified' AND cs.crawl_enabled
ORDER BY CASE ct.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
         cs.source_type, ct.canonical_name, cs.site_id;

\echo '=== HERE posting geography from stored snapshot ==='
SELECT CASE
         WHEN location LIKE 'US-%' THEN 'US'
         WHEN location IS NULL OR btrim(location) = '' THEN 'unknown'
         ELSE 'non-US'
       END AS market_scope,
       COUNT(*) AS active_jobs
FROM jobpush.job_postings
WHERE consolidation_key = '77-0080465' AND active
GROUP BY 1
ORDER BY 1;
