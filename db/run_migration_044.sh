#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> migration 044 exclude TechFetch aggregator"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/044_exclude_techfetch.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT target.consolidation_key,target.canonical_name,target.discovery_status,
          target.next_discovery_at,site.site_id,site.site_url,site.verification_status,
          site.review_notes
   FROM jobpush.crawl_targets target
   LEFT JOIN jobpush.career_sites site USING(consolidation_key)
   WHERE target.consolidation_key='22-3932852';
   SELECT domain,reason,active
   FROM jobpush.career_site_discovery_domain_excludes WHERE domain='techfetch.com';"
