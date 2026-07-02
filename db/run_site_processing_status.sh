#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off <<'SQL'
SELECT target.priority_tier,
       count(*) AS site_rows,
       count(*) FILTER (WHERE site.crawl_enabled) AS enabled_sites,
       count(DISTINCT site.consolidation_key) FILTER (WHERE site.crawl_enabled) AS enabled_companies,
       count(*) FILTER (
           WHERE site.crawl_enabled
             AND site.verification_status = 'verified'
             AND site.next_crawl_at <= now()
       ) AS due_enabled_sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
GROUP BY target.priority_tier
ORDER BY target.priority_tier;

SELECT target.priority_tier,
       count(DISTINCT site.consolidation_key) AS unresolved_generic_companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = false
  AND COALESCE(site.last_error, '') NOT LIKE 'generic_ats_resolution_attempted%'
GROUP BY target.priority_tier
ORDER BY target.priority_tier;

SELECT status,
       count(*) AS runs,
       count(*) FILTER (WHERE finished_at >= now() - interval '30 minutes') AS finished_last_30m,
       COALESCE(sum(parsed_job_count), 0) AS parsed_jobs,
       COALESCE(sum(new_job_count), 0) AS new_jobs,
       COALESCE(sum(target_job_count), 0) AS target_jobs
FROM jobpush.crawl_runs
WHERE started_at >= now() - interval '2 hours'
GROUP BY status
ORDER BY status;
SQL
