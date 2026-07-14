#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off <<'SQL'
\echo === Recent auto-trust vs schedule queue (P2/P3, last 48h) ===
WITH recent AS (
  SELECT site.site_id, site.source_type, site.verification_status, site.crawl_enabled,
         site.target_country_code, site.scope_method, site.next_crawl_at, site.crawl_status,
         site.last_success_at, site.reviewed_at, target.priority_tier
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.priority_tier IN ('P2','P3')
    AND site.reviewed_by = 'system:structured-ats-best-v5'
    AND site.reviewed_at >= now() - interval '48 hours'
    AND site.verification_status = 'verified'
    AND site.crawl_enabled
)
SELECT
  count(*) AS recent_verified,
  count(*) FILTER (WHERE q.site_id IS NOT NULL) AS in_schedule_queue,
  count(*) FILTER (WHERE q.is_due) AS due_now,
  count(*) FILTER (WHERE recent.last_success_at IS NULL) AS never_succeeded,
  count(*) FILTER (WHERE recent.next_crawl_at > now()) AS next_crawl_future,
  count(*) FILTER (WHERE coalesce(recent.target_country_code,'') <> 'US') AS non_us,
  count(*) FILTER (WHERE coalesce(recent.scope_method,'') IN ('','unknown')) AS bad_scope
FROM recent
LEFT JOIN jobpush.crawl_schedule_queue q USING (site_id);

\echo === Why recent verified sites are NOT in schedule queue ===
WITH recent AS (
  SELECT site.*
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.priority_tier IN ('P2','P3')
    AND site.reviewed_by = 'system:structured-ats-best-v5'
    AND site.reviewed_at >= now() - interval '48 hours'
    AND site.verification_status = 'verified'
    AND site.crawl_enabled
    AND NOT EXISTS (SELECT 1 FROM jobpush.crawl_schedule_queue q WHERE q.site_id = site.site_id)
)
SELECT source_type,
       target_country_code,
       scope_method,
       crawl_status,
       count(*) AS sites
FROM recent
GROUP BY 1,2,3,4
ORDER BY sites DESC
LIMIT 30;

\echo === Structured unverified not-enabled by source (dead-end inventory) ===
WITH not_enabled AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.source_type, site.site_url
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.verification_status='unverified'
    AND site.source_type <> 'generic_html'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier, source_type, count(*) AS companies
FROM not_enabled
GROUP BY 1,2
ORDER BY 1, companies DESC;

\echo === New grad bucket counts (dashboard_jobs_fast) ===
SELECT seniority_bucket, count(*) AS jobs
FROM jobpush.dashboard_jobs_fast
WHERE seniority_bucket IN ('internship','new_grad','entry_level','regular_full_time','senior_or_leadership')
GROUP BY 1
ORDER BY 1;
SQL
