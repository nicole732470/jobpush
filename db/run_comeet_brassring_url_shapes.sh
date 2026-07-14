#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off <<'SQL'
\echo === Comeet URL shapes ===
SELECT
  count(*) AS sites,
  count(*) FILTER (WHERE site_url ~* 'comeet\.(com|co)/jobs/[^/]+/[0-9A-F]+\.[0-9A-F]+') AS has_uid_path,
  count(*) FILTER (WHERE site_url ~* '[?&]token=') AS has_token,
  count(*) FILTER (WHERE site_url ~* 'comeet\.(com|co)/jobs/[^/?]+/?$') AS slug_only
FROM jobpush.career_sites
WHERE source_type='comeet';

SELECT left(site_url,160) AS url, verification_status
FROM jobpush.career_sites WHERE source_type='comeet'
ORDER BY CASE WHEN site_url ~* '/[0-9A-F]+\.[0-9A-F]+' THEN 0 ELSE 1 END, site_id
LIMIT 40;

\echo === Brassring URL shapes ===
SELECT
  count(*) AS sites,
  count(*) FILTER (WHERE site_url ~* 'partnerid=') AS has_partnerid,
  count(*) FILTER (WHERE site_url ~* 'siteid=') AS has_siteid,
  count(*) FILTER (WHERE site_url ~* 'login') AS loginish
FROM jobpush.career_sites WHERE source_type='brassring';

SELECT left(site_url,160) AS url, verification_status
FROM jobpush.career_sites WHERE source_type='brassring'
ORDER BY CASE WHEN site_url ~* 'partnerid=' THEN 0 ELSE 1 END, site_id
LIMIT 20;

\echo === Never-succeeded auto-trust: top boards to quarantine ===
SELECT site.source_type, site.site_id, left(site.site_url,100) AS url,
       left(coalesce(site.last_error,''),80) AS err, site.consecutive_failures
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.priority_tier IN ('P2','P3')
  AND site.reviewed_by='system:structured-ats-best-v5'
  AND site.reviewed_at >= now() - interval '7 days'
  AND site.verification_status='verified'
  AND site.crawl_enabled
  AND site.last_success_at IS NULL
ORDER BY site.consecutive_failures DESC NULLS LAST, site.source_type
LIMIT 40;
SQL
