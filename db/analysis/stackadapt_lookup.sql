SELECT target.consolidation_key, target.canonical_name, target.priority_tier,
       target.priority_score, target.discovery_status,
       site.site_id, site.site_url, site.source_type, site.verification_status,
       site.candidate_rank
FROM jobpush.crawl_targets target
LEFT JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.canonical_name ILIKE '%stackadapt%'
ORDER BY target.priority_score DESC, site.candidate_rank NULLS LAST, site.site_id;
