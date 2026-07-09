#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off -c "
SELECT queue.priority_tier,
       queue.priority_score,
       queue.canonical_name,
       site.site_id,
       site.site_url,
       site.normalized_domain,
       site.site_kind,
       site.verification_status,
       site.crawl_status,
       site.consecutive_failures
FROM jobpush.crawl_schedule_queue queue
JOIN jobpush.career_sites site USING (site_id)
WHERE queue.is_due
  AND queue.priority_tier = 'P2'
  AND queue.source_type = 'generic_html'
ORDER BY queue.priority_score DESC, site.site_id
LIMIT 50;
"
