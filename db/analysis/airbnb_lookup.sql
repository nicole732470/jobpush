\pset pager off

\echo '=== Airbnb company matches ==='
SELECT consolidation_key,
       canonical_name,
       crawl_priority_tier,
       lca_count,
       priority_score
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%airbnb%'
   OR consolidation_key ILIKE '%airbnb%'
ORDER BY lca_count DESC NULLS LAST, canonical_name;

\echo '=== Airbnb crawl target ==='
SELECT target.consolidation_key,
       target.canonical_name,
       target.priority_tier,
       target.priority_source,
       target.discovery_status,
       target.enabled
FROM jobpush.crawl_targets target
WHERE target.canonical_name ILIKE '%airbnb%'
   OR target.consolidation_key ILIKE '%airbnb%';

\echo '=== Airbnb career sites ==='
SELECT site.site_id,
       target.canonical_name,
       site.site_url,
       site.source_type,
       site.verification_status,
       site.crawl_enabled,
       site.crawl_status
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.canonical_name ILIKE '%airbnb%'
   OR target.consolidation_key ILIKE '%airbnb%'
ORDER BY site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST;
