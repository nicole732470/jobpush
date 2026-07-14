#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off <<'SQL'
\echo === Crawled today (America/Chicago) ===
SELECT
  count(DISTINCT site.site_id) AS sites_touched_today,
  count(DISTINCT site.site_id) FILTER (WHERE site.last_success_at::date = (now() AT TIME ZONE 'America/Chicago')::date) AS succeeded_today,
  count(DISTINCT site.site_id) FILTER (WHERE site.crawl_status='failed' AND site.updated_at::date = (now() AT TIME ZONE 'America/Chicago')::date) AS failed_touch_today
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.priority_tier IN ('P2','P3')
  AND site.verification_status='verified'
  AND site.crawl_enabled
  AND (
    site.last_crawled_at >= date_trunc('day', now() AT TIME ZONE 'America/Chicago') AT TIME ZONE 'America/Chicago'
    OR site.last_success_at >= date_trunc('day', now() AT TIME ZONE 'America/Chicago') AT TIME ZONE 'America/Chicago'
  );

\echo === Verified enabled due / never crawled / last crawl age ===
SELECT
  count(*) AS verified_enabled,
  count(*) FILTER (WHERE q.is_due) AS due_now,
  count(*) FILTER (WHERE site.last_success_at IS NULL) AS never_succeeded,
  count(*) FILTER (WHERE site.last_crawled_at IS NULL) AS never_crawled,
  count(*) FILTER (WHERE site.last_crawled_at >= now() - interval '1 day') AS crawled_24h,
  count(*) FILTER (WHERE site.last_crawled_at >= now() - interval '7 days') AS crawled_7d
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN jobpush.crawl_schedule_queue q USING (site_id)
WHERE target.priority_tier IN ('P2','P3')
  AND site.verification_status='verified'
  AND site.crawl_enabled;

\echo === Recent never-succeeded / failed auto-trust error samples ===
SELECT site.source_type, left(coalesce(site.last_error,'(null)'),120) AS err, count(*) AS n
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.priority_tier IN ('P2','P3')
  AND site.reviewed_by='system:structured-ats-best-v5'
  AND site.reviewed_at >= now() - interval '7 days'
  AND site.verification_status='verified'
  AND site.crawl_enabled
  AND (site.last_success_at IS NULL OR site.crawl_status='failed')
GROUP BY 1,2
ORDER BY n DESC
LIMIT 25;

\echo === Comeet / Brassring candidates (any status, P2/P3) ===
SELECT site.source_type, site.verification_status, site.crawl_enabled, count(*) AS sites,
       count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled AND target.priority_tier IN ('P2','P3')
  AND site.source_type IN ('comeet','brassring')
GROUP BY 1,2,3
ORDER BY 1,2,3;

\echo === Sample comeet/brassring URLs ===
SELECT site.source_type, site.verification_status, left(site.site_url,140) AS url
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled AND target.priority_tier IN ('P2','P3')
  AND site.source_type IN ('comeet','brassring')
ORDER BY site.source_type, site.verification_status, site.site_id
LIMIT 30;
SQL
