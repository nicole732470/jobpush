\echo '=== company_targets_consolidated ==='
SELECT consolidation_key, canonical_name, crawl_priority_tier, priority_score
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%harvey%'
   OR consolidation_key ILIKE '%harvey%'
ORDER BY priority_score DESC NULLS LAST;

\echo '=== crawl_targets + career_sites ==='
SELECT target.consolidation_key, target.canonical_name, target.priority_tier,
       target.discovery_status, target.enabled,
       site.site_id, site.site_url, site.source_type,
       site.verification_status, site.crawl_enabled, site.reviewed_by
FROM jobpush.crawl_targets target
LEFT JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.canonical_name ILIKE '%harvey%'
   OR target.consolidation_key ILIKE '%harvey%'
   OR site.site_url ILIKE '%harvey%'
   OR site.normalized_domain ILIKE '%harvey%'
ORDER BY site.candidate_rank NULLS LAST, site.site_id;

\echo '=== career_sites by URL/domain ==='
SELECT site_id, consolidation_key, site_url, normalized_domain,
       source_type, verification_status, crawl_enabled, reviewed_by
FROM jobpush.career_sites
WHERE site_url ILIKE '%harvey%'
   OR normalized_domain ILIKE '%harvey%'
   OR consolidation_key ILIKE '%harvey%'
ORDER BY site_id;
