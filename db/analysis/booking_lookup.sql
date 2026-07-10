\echo '=== companies (name ILIKE booking) ==='
SELECT fein, name, city, state
FROM public.companies
WHERE name ILIKE '%booking%'
ORDER BY name
LIMIT 30;

\echo '=== company_aliases ==='
SELECT ca.fein, ca.alias_name, c.name AS company_name
FROM public.company_aliases ca
JOIN public.companies c ON c.fein = ca.fein
WHERE ca.alias_name ILIKE '%booking%'
   OR c.name ILIKE '%booking%'
ORDER BY ca.alias_name
LIMIT 30;

\echo '=== company_targets_consolidated ==='
SELECT consolidation_key, canonical_name, priority_score,
       computed_crawl_priority_tier, crawl_priority_tier, lca_count
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%booking%'
ORDER BY lca_count DESC NULLS LAST
LIMIT 20;

\echo '=== priceline / kayak (booking holdings) ==='
SELECT consolidation_key, canonical_name, priority_score,
       computed_crawl_priority_tier, crawl_priority_tier, lca_count
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%priceline%'
   OR canonical_name ILIKE '%kayak%'
ORDER BY lca_count DESC NULLS LAST
LIMIT 20;

\echo '=== career_sites ==='
SELECT cs.site_id, ct.canonical_name, cs.site_url, cs.verification_status,
       cs.crawl_status, cs.crawl_enabled, cs.last_success_at
FROM jobpush.career_sites cs
JOIN jobpush.company_targets_consolidated ct
  ON ct.consolidation_key = cs.consolidation_key
WHERE ct.canonical_name ILIKE '%booking%'
   OR ct.canonical_name ILIKE '%priceline%'
   OR ct.canonical_name ILIKE '%kayak%'
ORDER BY ct.canonical_name, cs.site_url
LIMIT 30;

\echo '=== crawl_targets ==='
SELECT ct.consolidation_key, ct.canonical_name, ct.enabled, ct.priority_rank
FROM jobpush.crawl_targets ct
WHERE ct.canonical_name ILIKE '%booking%'
   OR ct.canonical_name ILIKE '%priceline%'
   OR ct.canonical_name ILIKE '%kayak%'
ORDER BY ct.canonical_name
LIMIT 20;
