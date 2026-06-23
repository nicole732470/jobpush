\echo '=== Grubhub consolidated rows ==='
SELECT consolidation_key, canonical_name, priority_score,
       computed_crawl_priority_tier, crawl_priority_tier
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%grubhub%'
ORDER BY lca_count DESC;
