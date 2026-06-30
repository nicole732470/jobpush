\pset pager off

SELECT
    target.priority_tier,
    target.priority_score,
    target.canonical_name,
    site.consolidation_key,
    site.site_id,
    site.source_type,
    site.source_key,
    site.site_url,
    site.normalized_domain,
    site.verification_status,
    site.crawl_enabled,
    site.crawl_status,
    left(coalesce(site.last_error, ''), 240) AS last_error_excerpt
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.last_error LIKE '%quarantined_failed_active_site_2026_06_30%'
ORDER BY target.priority_tier, target.priority_score DESC NULLS LAST, target.canonical_name, site.site_id;
