#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/ops/canonicalize_workday_job_details_p2_p3.sql"
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"
echo '=== Workday not-enabled remainder ==='
"${PSQL[@]}" -P pager=off <<'SQL'
SELECT target.priority_tier,
       count(*) FILTER (WHERE site.verification_status='unverified' AND site.site_url ~* '/job/') AS detail_unverified,
       count(*) FILTER (WHERE site.verification_status='unverified' AND site.site_url !~* '/job/') AS board_unverified,
       count(*) FILTER (WHERE site.verification_status='verified' AND site.crawl_enabled
                         AND site.reviewed_at >= now() - interval '15 minutes') AS newly_verified_15m
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled AND target.priority_tier IN ('P2','P3')
  AND site.source_type='workday'
GROUP BY 1 ORDER BY 1;
SQL
