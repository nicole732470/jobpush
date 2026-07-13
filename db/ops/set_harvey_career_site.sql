-- Harvey AI (harvey.ai): no LCA FEIN in public.companies — seed a brand key
-- and verify the official Ashby board behind https://www.harvey.ai/careers.

\pset pager off

BEGIN;

INSERT INTO jobpush.company_targets_consolidated (
    consolidation_key,
    canonical_name,
    is_merged_group,
    linkedin_employer_key,
    member_fein_count,
    member_feins,
    primary_fein,
    employer_city,
    employer_state,
    lca_count,
    certified_count,
    single_lca_company,
    target_role_lca_count,
    target_role_valid_salary_lca_count,
    target_role_invalid_salary_lca_count,
    product_role_lca_count,
    product_role_lca_pct,
    recent_lca,
    target_role_score,
    lca_count_score,
    chicago_score,
    product_role_score,
    product_manager_score,
    salary_score,
    linkedin_top_employer_score,
    priority_score,
    computed_crawl_priority_tier,
    crawl_priority_tier,
    priority_version,
    executive_only_excluded,
    priority_exclusion_reason,
    updated_at
)
VALUES (
    'harvey',
    'Harvey',
    FALSE,
    NULL,
    1,
    '{}'::text[],
    NULL,
    'San Francisco',
    'CA',
    0,
    0,
    FALSE,
    0,
    0,
    0,
    0,
    0,
    FALSE,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    NULL,
    'P0',
    'manual-brand-seed-v1',
    FALSE,
    'Manual brand seed: Harvey AI (harvey.ai) has no LCA FEIN yet',
    now()
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    canonical_name = EXCLUDED.canonical_name,
    crawl_priority_tier = EXCLUDED.crawl_priority_tier,
    priority_exclusion_reason = EXCLUDED.priority_exclusion_reason,
    priority_version = EXCLUDED.priority_version,
    updated_at = now();

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES (
    'harvey',
    'P0',
    'Manual networking priority: Harvey AI (harvey.ai) Ashby careers',
    'nicole',
    TRUE
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();

INSERT INTO jobpush.crawl_targets (
    consolidation_key,
    canonical_name,
    priority_tier,
    computed_priority_tier,
    priority_source,
    priority_override_reason,
    priority_score,
    enabled,
    discovery_status,
    next_discovery_at,
    created_at,
    updated_at
)
VALUES (
    'harvey',
    'Harvey',
    'P0',
    NULL,
    'manual_override',
    'Manual networking priority: Harvey AI (harvey.ai) Ashby careers',
    0,
    TRUE,
    'found',
    NULL,
    now(),
    now()
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    canonical_name = EXCLUDED.canonical_name,
    priority_tier = EXCLUDED.priority_tier,
    computed_priority_tier = EXCLUDED.computed_priority_tier,
    priority_source = EXCLUDED.priority_source,
    priority_override_reason = EXCLUDED.priority_override_reason,
    enabled = TRUE,
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now();

SELECT jobpush.add_verified_career_site(
    'harvey',
    'https://jobs.ashbyhq.com/harvey',
    'ashby',
    'harvey',
    'US',
    'local_filter',
    'nicole',
    'Official Harvey AI Ashby board (jobs behind https://www.harvey.ai/careers#open-roles)'
);

COMMIT;

SELECT target.consolidation_key,
       target.canonical_name,
       target.priority_tier,
       target.priority_source,
       target.enabled,
       target.discovery_status,
       site.site_id,
       site.site_url,
       site.source_type,
       site.source_key,
       site.verification_status,
       site.crawl_enabled,
       site.target_country_code,
       site.scope_method,
       site.next_crawl_at
FROM jobpush.crawl_targets target
JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.consolidation_key = 'harvey'
ORDER BY site.site_id;
