#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
\echo '=== ApplyToJob high-volume sites ==='
WITH latest AS (
    SELECT DISTINCT ON (run.site_id)
           run.site_id,
           run.raw_job_count,
           run.target_job_count,
           run.review_job_count,
           run.new_job_count,
           run.finished_at
    FROM jobpush.crawl_runs run
    JOIN jobpush.career_sites site USING (site_id)
    WHERE site.source_type = 'applytojob'
    ORDER BY run.site_id, run.started_at DESC NULLS LAST, run.run_id DESC
)
SELECT target.priority_tier,
       target.canonical_name,
       site.site_id,
       latest.raw_job_count,
       latest.target_job_count,
       latest.review_job_count,
       round(100.0 * COALESCE(latest.review_job_count, 0) / NULLIF(latest.raw_job_count, 0), 1) AS review_pct,
       site.site_url
FROM latest
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE COALESCE(latest.raw_job_count, 0) >= 100
   OR COALESCE(latest.review_job_count, 0) >= 50
ORDER BY latest.raw_job_count DESC NULLS LAST, latest.review_job_count DESC NULLS LAST
LIMIT 30;

\echo '=== ApplyToJob top review titles ==='
SELECT posting.normalized_title,
       min(posting.title) AS example_title,
       COUNT(*) AS active_us_postings,
       COUNT(DISTINCT posting.consolidation_key) AS companies,
       string_agg(DISTINCT target.priority_tier, ', ' ORDER BY target.priority_tier) AS tiers
FROM jobpush.job_postings posting
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target ON target.consolidation_key = posting.consolidation_key
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE site.source_type = 'applytojob'
  AND posting.active
  AND posting.market_scope = 'US'
  AND label.classification_status = 'review'
GROUP BY posting.normalized_title
ORDER BY active_us_postings DESC, companies DESC
LIMIT 60;

\echo '=== ApplyToJob top target titles ==='
SELECT posting.normalized_title,
       min(posting.title) AS example_title,
       COUNT(*) AS active_us_postings,
       COUNT(DISTINCT posting.consolidation_key) AS companies,
       string_agg(DISTINCT target.priority_tier, ', ' ORDER BY target.priority_tier) AS tiers
FROM jobpush.job_postings posting
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target ON target.consolidation_key = posting.consolidation_key
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE site.source_type = 'applytojob'
  AND posting.active
  AND posting.market_scope = 'US'
  AND label.classification_status = 'target'
GROUP BY posting.normalized_title
ORDER BY active_us_postings DESC, companies DESC
LIMIT 40;
SQL
