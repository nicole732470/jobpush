#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/088_profile_avoid_rules_media_education_aerospace.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT decision_reason, COUNT(*) AS titles
   FROM jobpush.job_title_label_history
   WHERE decision_reason IN (
          'profile_avoid_producer_media_roles: candidate_profile 2026-06-28',
          'profile_avoid_teacher_education_roles: candidate_profile 2026-06-28',
          'profile_avoid_warehouse_logistics_roles: candidate_profile 2026-06-28',
          'profile_avoid_aerospace_aviation_roles: candidate_profile 2026-06-28',
          'profile_avoid_performance_roles: candidate_profile 2026-06-28'
      )
   GROUP BY 1
   ORDER BY titles DESC, decision_reason;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT role_status, count(*) AS active_us_jobs
   FROM jobpush.dashboard_jobs
   GROUP BY 1
   ORDER BY 1;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT count(*) AS remaining_review_titles FROM jobpush.job_title_review_queue;"
