\echo '=== google row shape ==='
SELECT consolidation_key, canonical_name, is_merged_group, linkedin_employer_key,
       crawl_priority_tier, computed_crawl_priority_tier, priority_score,
       target_role_score, linkedin_top_employer_score
FROM jobpush.company_targets_consolidated
WHERE consolidation_key IN ('google','hsbc','airbnb')
ORDER BY consolidation_key;

\d jobpush.company_targets_consolidated

\echo '=== crawl_targets columns ==='
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='jobpush' AND table_name='crawl_targets'
ORDER BY ordinal_position;

\echo '=== any harvey.ai domain anywhere ==='
SELECT consolidation_key, site_url FROM jobpush.career_sites WHERE site_url ILIKE '%harvey.ai%' OR site_url ILIKE '%ashbyhq.com/harvey%';
