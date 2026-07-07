#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
\echo '=== target companies by tier and coverage ==='
SELECT target.priority_tier,
       COUNT(*) AS companies,
       COUNT(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM jobpush.career_sites site
          WHERE site.consolidation_key=target.consolidation_key
            AND site.verification_status='verified'
            AND site.crawl_enabled
       )) AS companies_with_enabled_site,
       COUNT(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM jobpush.career_sites site
          WHERE site.consolidation_key=target.consolidation_key
            AND site.verification_status='verified'
            AND site.crawl_enabled
            AND site.last_success_at IS NOT NULL
       )) AS companies_succeeded_once,
       COUNT(*) FILTER (WHERE NOT EXISTS (
          SELECT 1 FROM jobpush.career_sites site
          WHERE site.consolidation_key=target.consolidation_key
            AND site.verification_status='verified'
            AND site.crawl_enabled
       )) AS companies_need_site_resolution
FROM jobpush.crawl_targets target
WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2','P3','P4')
GROUP BY target.priority_tier
ORDER BY target.priority_tier;

\echo '=== enabled/success/failed by tier ==='
SELECT target.priority_tier,
       COUNT(*) FILTER (WHERE site.verification_status='verified' AND site.crawl_enabled) AS enabled_sites,
       COUNT(*) FILTER (WHERE site.verification_status='verified' AND site.crawl_enabled AND site.last_success_at IS NOT NULL) AS succeeded_once,
       COUNT(*) FILTER (WHERE site.verification_status='verified' AND site.crawl_enabled AND site.crawl_status='failed') AS failed_now,
       COUNT(*) FILTER (WHERE site.verification_status='verified' AND site.crawl_enabled AND queue.is_due) AS due_now
FROM jobpush.crawl_targets target
LEFT JOIN jobpush.career_sites site USING (consolidation_key)
LEFT JOIN jobpush.crawl_schedule_queue queue ON queue.site_id = site.site_id
WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2','P3','P4')
GROUP BY target.priority_tier
ORDER BY target.priority_tier;

\echo '=== crawl interval distribution ==='
SELECT target.priority_tier,
       site.crawl_interval_hours,
       COUNT(*) AS enabled_sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND site.verification_status='verified'
  AND site.crawl_enabled
GROUP BY target.priority_tier, site.crawl_interval_hours
ORDER BY target.priority_tier, site.crawl_interval_hours;

\echo '=== source type coverage ==='
SELECT site.source_type,
       COUNT(*) AS enabled_sites,
       COUNT(*) FILTER (WHERE site.last_success_at IS NOT NULL) AS succeeded_once,
       COUNT(*) FILTER (WHERE site.crawl_status='failed') AS failed_now,
       SUM(CASE WHEN target.priority_tier='P0' THEN 1 ELSE 0 END) AS p0,
       SUM(CASE WHEN target.priority_tier='P1' THEN 1 ELSE 0 END) AS p1,
       SUM(CASE WHEN target.priority_tier='P2' THEN 1 ELSE 0 END) AS p2,
       SUM(CASE WHEN target.priority_tier='P3' THEN 1 ELSE 0 END) AS p3
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND site.verification_status='verified'
  AND site.crawl_enabled
GROUP BY site.source_type
ORDER BY enabled_sites DESC
LIMIT 30;

\echo '=== unresolved generic candidates ==='
SELECT target.priority_tier,
       COUNT(*) FILTER (WHERE site.source_type='generic_html' AND site.verification_status='unverified' AND NOT site.crawl_enabled) AS unverified_generic_candidates,
       COUNT(DISTINCT target.consolidation_key) FILTER (WHERE site.source_type='generic_html' AND site.verification_status='unverified' AND NOT site.crawl_enabled) AS companies_with_unverified_generic_candidate,
       COUNT(DISTINCT target.consolidation_key) FILTER (WHERE NOT EXISTS (
          SELECT 1 FROM jobpush.career_sites verified
          WHERE verified.consolidation_key=target.consolidation_key
            AND verified.verification_status='verified'
            AND verified.crawl_enabled
       )) AS companies_without_enabled_site
FROM jobpush.crawl_targets target
LEFT JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2','P3','P4')
GROUP BY target.priority_tier
ORDER BY target.priority_tier;
SQL
