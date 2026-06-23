\echo '=== Review queue (companies still pending) ==='
SELECT COUNT(*) AS companies_in_queue
FROM jobpush.career_site_company_review_queue;

\echo '=== By priority tier ==='
SELECT priority_tier, COUNT(*) AS companies
FROM jobpush.career_site_company_review_queue
GROUP BY priority_tier
ORDER BY priority_tier;

\echo '=== Discovery status breakdown (enabled crawl_targets) ==='
SELECT discovery_status, COUNT(*) AS companies
FROM jobpush.crawl_targets
WHERE enabled
GROUP BY discovery_status
ORDER BY companies DESC;

\echo '=== Career site verification (all sites on enabled targets) ==='
SELECT site.verification_status, COUNT(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets ct ON ct.consolidation_key = site.consolidation_key
WHERE ct.enabled
GROUP BY site.verification_status
ORDER BY sites DESC;

\echo '=== Resolved: found + has verified site ==='
SELECT COUNT(DISTINCT ct.consolidation_key) AS companies_with_verified_site
FROM jobpush.crawl_targets ct
JOIN jobpush.career_sites site
  ON site.consolidation_key = ct.consolidation_key
 AND site.verification_status = 'verified'
 AND site.crawl_enabled
WHERE ct.enabled AND ct.discovery_status = 'found';

\echo '=== Manually reviewed sites ==='
SELECT verification_status, COUNT(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_at IS NOT NULL
GROUP BY verification_status;

\echo '=== Ever had Tavily discovery + now resolved ==='
SELECT
    COUNT(*) FILTER (WHERE ct.discovery_status = 'found') AS found,
    COUNT(*) FILTER (WHERE ct.discovery_status = 'review_pending') AS review_pending,
    COUNT(*) FILTER (WHERE ct.discovery_status = 'not_found') AS not_found
FROM jobpush.crawl_targets ct
WHERE ct.enabled
  AND EXISTS (
      SELECT 1 FROM jobpush.career_sites s
      WHERE s.consolidation_key = ct.consolidation_key
        AND s.discovery_source = 'tavily_basic'
  );
