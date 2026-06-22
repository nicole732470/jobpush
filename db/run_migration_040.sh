#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 040 Apple career site"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/040_apple_career_site.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT ct.canonical_name, ct.priority_tier, ct.priority_score,
          cs.site_id, cs.site_url, cs.source_type, cs.verification_status,
          cs.target_country_code, cs.crawl_enabled
   FROM jobpush.crawl_targets ct
   LEFT JOIN jobpush.career_sites cs USING (consolidation_key)
   WHERE ct.consolidation_key='apple'
   ORDER BY cs.site_id;"
