\pset pager off
\echo '=== Enabled companies now ==='
SELECT target.priority_tier, count(DISTINCT target.consolidation_key) AS enabled_companies
FROM jobpush.crawl_targets target
WHERE target.enabled
  AND target.priority_tier IN ('P2','P3')
  AND EXISTS (
    SELECT 1 FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.verification_status='verified'
      AND site.crawl_enabled
  )
GROUP BY 1 ORDER BY 1;

\echo '=== Auto-trusted after generic resolve (recent) ==='
SELECT reviewed_by, source_type, count(*) AS sites,
       count(*) FILTER (WHERE last_success_at IS NOT NULL) AS crawled_ok
FROM jobpush.career_sites
WHERE reviewed_by IN ('system:structured-ats-best-v5','system:ats-url-guess-v1')
  AND reviewed_at >= now() - interval '3 hours'
GROUP BY 1,2
ORDER BY 1, sites DESC;

\echo '=== Sites created by generic_html_ats_resolve recently ==='
SELECT source_type, verification_status, crawl_enabled, count(*) AS sites
FROM jobpush.career_sites
WHERE discovery_source ILIKE '%resolve%'
  AND created_at >= now() - interval '3 hours'
GROUP BY 1,2,3
ORDER BY sites DESC;

\echo '=== discovery_source for sites created last 3h ==='
SELECT coalesce(discovery_source,'(null)') AS discovery_source, count(*) AS sites
FROM jobpush.career_sites
WHERE created_at >= now() - interval '3 hours'
GROUP BY 1 ORDER BY sites DESC
LIMIT 20;

\echo '=== Remaining generic-only JSON-LD-checked (approx) ==='
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.source_type, site.last_error
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.verification_status='unverified'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier,
       count(*) FILTER (WHERE source_type='generic_html' AND coalesce(last_error,'') LIKE 'generic_jsonld_checked:%') AS generic_jsonld_checked,
       count(*) FILTER (WHERE source_type<>'generic_html') AS structured_unverified,
       count(*) AS total_not_enabled_with_candidate
FROM rank1
GROUP BY 1 ORDER BY 1;
