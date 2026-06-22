#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/connect_rds.sh
source "$DB_DIR/lib/connect_rds.sh"

SKIP_FILING_STATS=0
SKIP_PER_FEIN=0
ONLY=""

usage() {
  cat <<'EOF'
Usage: run_refresh_pipeline.sh [options]

Rebuild JobPush priority tables. All writes stay in jobpush schema.

Options:
  --skip-filing-stats   Skip lca_cases scan (use after rule-only config changes)
  --skip-per-fein       Skip jobpush.company_targets audit refresh
  --only NAME           Run one step: filing-stats | per-fein | consolidated

Typical flows:
  Full rebuild (new LCA data or wage repair):
    bash db/refresh/run_refresh_pipeline.sh

  LinkedIn or consolidation config only:
    bash db/refresh/run_refresh_pipeline.sh --skip-filing-stats

  Crawl queue only (filing stats already fresh):
    bash db/refresh/run_refresh_pipeline.sh --skip-filing-stats --skip-per-fein
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-filing-stats) SKIP_FILING_STATS=1 ;;
    --skip-per-fein) SKIP_PER_FEIN=1 ;;
    --only)
      shift
      ONLY="${1:-}"
      if [[ -z "$ONLY" ]]; then
        echo "--only requires a step name" >&2
        exit 2
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

run_step() {
  local label="$1"
  local sql_file="$2"
  echo "==> $label"
  /usr/bin/time -p "${PSQL[@]}" -c '\timing on' -f "$sql_file"
}

should_run() {
  local step="$1"
  if [[ -n "$ONLY" && "$ONLY" != "$step" ]]; then
    return 1
  fi
  case "$step" in
    filing-stats) [[ "$SKIP_FILING_STATS" -eq 0 ]] ;;
    per-fein) [[ "$SKIP_PER_FEIN" -eq 0 ]] ;;
    consolidated) true ;;
    *) return 1 ;;
  esac
}

if should_run filing-stats; then
  run_step "employer_filing_stats (single lca_cases scan)" \
    "$SCRIPT_DIR/refresh_employer_filing_stats.sql"
fi

if should_run per-fein; then
  run_step "company_targets per-FEIN audit" \
    "$SCRIPT_DIR/refresh_company_targets.sql"
fi

if should_run consolidated; then
  run_step "company_targets_consolidated crawl queue" \
    "$SCRIPT_DIR/refresh_company_targets_consolidated.sql"
fi

"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(*) AS employer_filing_stats_rows FROM jobpush.employer_filing_stats;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(*) AS consolidated_rows,
          MAX(priority_score) AS max_priority
   FROM jobpush.company_targets_consolidated;"
