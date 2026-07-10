\pset pager off

\echo '=== IXL lookup ==='
SELECT consolidation_key, canonical_name, crawl_priority_tier, lca_count
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%ixl learning%'
   OR canonical_name ILIKE '%ixl center%'
ORDER BY lca_count DESC NULLS LAST;

\echo '=== IXL career sites ==='
SELECT cs.site_id, ct.canonical_name, cs.site_url, cs.verification_status,
       cs.crawl_enabled, cs.crawl_status, cs.last_success_at
FROM jobpush.career_sites cs
JOIN jobpush.company_targets_consolidated ct
  ON ct.consolidation_key = cs.consolidation_key
WHERE ct.canonical_name ILIKE '%ixl learning%'
ORDER BY cs.site_url;
