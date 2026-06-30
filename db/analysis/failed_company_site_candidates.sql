\pset pager off

WITH failed_companies AS (
    SELECT DISTINCT site.consolidation_key
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2')
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
)
SELECT
    target.priority_tier,
    target.priority_score,
    target.canonical_name,
    site.consolidation_key,
    site.site_id,
    site.candidate_rank,
    site.candidate_score,
    site.verification_status,
    site.crawl_enabled,
    site.crawl_status,
    site.source_type,
    site.source_key,
    site.site_url,
    site.normalized_domain,
    site.discovery_source,
    site.reviewed_by,
    left(coalesce(site.last_error, ''), 160) AS last_error_excerpt
FROM failed_companies failed
JOIN jobpush.crawl_targets target USING (consolidation_key)
JOIN jobpush.career_sites site USING (consolidation_key)
ORDER BY target.priority_tier, target.priority_score DESC NULLS LAST, target.canonical_name,
         site.crawl_enabled DESC, site.verification_status, site.candidate_score DESC NULLS LAST, site.site_id;
