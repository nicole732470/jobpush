\pset pager off

\echo '=== eightfold URL hosts/paths ==='
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.site_id, site.normalized_domain, site.site_url
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.verification_status='unverified' AND site.source_type='eightfold'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier,
       CASE
         WHEN site_url ~* 'eightfold\.ai/.*/privacy' OR site_url ILIKE '%vs-errors.eightfold.ai%' THEN 'bad_privacy_or_error'
         WHEN normalized_domain LIKE '%.eightfold.ai' AND site_url ~* '/careers' THEN 'tenant_careers'
         WHEN normalized_domain LIKE '%.eightfold.ai' THEN 'tenant_other'
         ELSE 'custom_host_' || coalesce(normalized_domain,'?')
       END AS shape,
       count(*) AS n,
       min(site_url) AS sample
FROM rank1
GROUP BY 1,2 ORDER BY 1, n DESC;

\echo '=== gusto URL shapes ==='
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.site_id, site.normalized_domain, site.site_url, site.last_error
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.verification_status='unverified' AND site.source_type='gusto'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier,
       CASE
         WHEN site_url ~* '^https?://jobs\.gusto\.com/boards/[^/?#]+/?$' THEN 'boards_root'
         WHEN normalized_domain='jobs.gusto.com' THEN 'boards_other'
         ELSE 'other'
       END AS shape,
       count(*) AS n,
       min(site_url) AS sample
FROM rank1
GROUP BY 1,2 ORDER BY 1, n DESC;

\echo '=== successfactors / brassring / comeet / trinethire / talentbrew samples ==='
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.source_type, site.normalized_domain, site.site_url
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.verification_status='unverified'
    AND site.source_type IN ('successfactors','brassring','comeet','trinethire','talentbrew','cognizant_jobs')
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT source_type, priority_tier, count(*) AS n,
       count(*) FILTER (WHERE normalized_domain ~* 'career[0-9]*\.successfactors\.com') AS sf_career_shell,
       count(*) FILTER (WHERE site_url ~* '/career/?$') AS ends_career,
       min(site_url) AS sample
FROM rank1
GROUP BY 1,2 ORDER BY 1,2;

\echo '=== already-enabled eightfold/gusto health ==='
SELECT site.source_type, target.priority_tier, site.crawl_status, count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.source_type IN ('eightfold','gusto')
  AND site.verification_status='verified' AND site.crawl_enabled
  AND target.priority_tier IN ('P0','P1','P2','P3')
GROUP BY 1,2,3 ORDER BY 1,2,3;
