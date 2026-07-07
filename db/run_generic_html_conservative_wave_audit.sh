#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off <<'SQL'
WITH wave_sites AS (
    SELECT site.site_id, target.priority_tier, site.crawl_status, site.last_error
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE site.reviewed_by = 'system:generic-html-conservative-wave-v1'
), run_rollup AS (
    SELECT run.site_id,
           count(*) AS runs,
           count(*) FILTER (WHERE run.status='succeeded') AS succeeded_runs,
           count(*) FILTER (WHERE run.status='failed') AS failed_runs,
           coalesce(sum(run.parsed_job_count), 0) AS parsed_jobs,
           coalesce(sum(run.new_job_count), 0) AS new_jobs,
           coalesce(sum(run.target_job_count), 0) AS target_jobs,
           coalesce(sum(run.review_job_count), 0) AS review_jobs
    FROM jobpush.crawl_runs run
    JOIN wave_sites site USING (site_id)
    WHERE run.started_at >= now() - interval '4 hours'
    GROUP BY run.site_id
)
SELECT site.priority_tier,
       count(*) AS enabled_sites,
       count(*) FILTER (WHERE rollup.runs IS NOT NULL) AS attempted_sites,
       count(*) FILTER (WHERE rollup.succeeded_runs > 0) AS success_sites,
       count(*) FILTER (WHERE rollup.failed_runs > 0) AS failed_sites,
       coalesce(sum(rollup.parsed_jobs), 0) AS parsed_jobs,
       coalesce(sum(rollup.new_jobs), 0) AS new_jobs,
       coalesce(sum(rollup.target_jobs), 0) AS target_jobs,
       coalesce(sum(rollup.review_jobs), 0) AS review_jobs
FROM wave_sites site
LEFT JOIN run_rollup rollup USING (site_id)
GROUP BY site.priority_tier
ORDER BY site.priority_tier;

WITH wave_sites AS (
    SELECT site.site_id, target.priority_tier, site.crawl_status, site.last_error
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE site.reviewed_by = 'system:generic-html-conservative-wave-v1'
)
SELECT site.crawl_status,
       left(coalesce(site.last_error, ''), 120) AS last_error,
       count(*) AS sites
FROM wave_sites site
GROUP BY site.crawl_status, left(coalesce(site.last_error, ''), 120)
ORDER BY sites DESC, crawl_status
LIMIT 20;
SQL
