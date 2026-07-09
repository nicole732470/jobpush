#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" <<'SQL'
SELECT
    role_stack,
    role_family,
    COUNT(*) AS open_jobs
FROM jobpush.dashboard_jobs_fast
WHERE role_status = 'target'
  AND (
      role_family IN ('product_manager', 'project_manager', 'program_manager')
      OR normalized_title LIKE '%product%manager%'
      OR normalized_title LIKE '%project%manager%'
      OR normalized_title LIKE '%program%manager%'
      OR canonical_role ILIKE '%information technology project manager%'
  )
GROUP BY role_stack, role_family
ORDER BY role_stack, role_family;
SQL
