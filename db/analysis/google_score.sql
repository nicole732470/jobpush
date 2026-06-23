SELECT consolidation_key, canonical_name, is_merged_group, member_fein_count,
       lca_count, target_role_lca_count, priority_score, crawl_priority_tier,
       target_role_score, lca_count_score, chicago_score,
       product_role_score, product_manager_score, salary_score,
       linkedin_top_employer_score, linkedin_employer_key,
       target_role_min_annual_salary, priority_version
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%google%'
   OR consolidation_key IN ('google', 'alphabet-google')
   OR linkedin_employer_key IN ('google', 'alphabet-google')
ORDER BY lca_count DESC;
