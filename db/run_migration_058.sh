#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/058_self_service_career_operations.sql"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -c \
  "SELECT proname
   FROM pg_proc
   JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
   WHERE nspname = 'jobpush'
     AND proname IN (
       'add_verified_career_site', 'verify_career_site_candidate',
       'reject_all_career_site_candidates', 'set_manual_crawl_priority'
     )
   ORDER BY proname;"
