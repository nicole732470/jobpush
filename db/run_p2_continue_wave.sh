#!/usr/bin/env bash
# P2 ops continuation: safe defaults only.
# ponytail: big crawls/guessing must be explicitly enabled; this script is run from SSM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "=== P2 snapshot (before) ==="
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/analysis/p2_failed_crawl_distribution.sql"

echo "=== Step 1: reject obvious bad failed URLs (P0-P2) ==="
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/ops/reject_obvious_bad_failed_sites.sql" || true

echo "=== Step 2: resolve transient failures + demote stale 404 URLs ==="
bash "$SCRIPT_DIR/run_resolve_current_failed_sites.sh"

echo "=== Step 3: quarantine chronic P2 failures (iCIMS/generic timeout, Workday payload, GH 404) ==="
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/ops/quarantine_p2_chronic_failures.sql"

echo "=== Step 4: auto-trust ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Step 5: P2 fast-source due crawl only ==="
bash "$SCRIPT_DIR/run_due_crawl_p2_fast_structured_wave.sh"

if [[ "${RUN_P2_ATS_GUESS:-0}" == "1" ]]; then
  echo "=== Step 6: optional zero-credit ATS guess P2+P3 ==="
  ATS_GUESS_TIERS=P2,P3 ATS_GUESS_LIMIT="${ATS_GUESS_LIMIT:-100}" \
    bash "$SCRIPT_DIR/run_guess_ats_sites.sh"
else
  echo "=== Step 6: skip ATS guessing by default ==="
fi

echo "=== Step 8: auto-trust after guess ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Step 9: zero-credit generic HTML hidden ATS resolver P2 ==="
GENERIC_RESOLVE_TIERS=P2 GENERIC_RESOLVE_LIMIT="${GENERIC_RESOLVE_LIMIT:-200}" \
  bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh"

echo "=== Step 10: final auto-trust ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== P2 snapshot (after) ==="
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/analysis/p2_failed_crawl_distribution.sql"
bash "$SCRIPT_DIR/run_p2_crawl_blockers.sh"
