#!/usr/bin/env bash
# P2 expansion: auto-trust (incl. iCIMS) + zero-credit resolver/guess.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Step 1: auto-trust (workday/workable/icims/...) ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Step 2: zero-credit ATS guess P2 (limit=2000) ==="
ATS_GUESS_TIERS=P2 ATS_GUESS_LIMIT=2000 bash "$SCRIPT_DIR/run_guess_ats_sites.sh"

echo "=== Step 3: auto-trust after ATS guess ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Step 4: zero-credit generic HTML resolver P2 (limit=2000) ==="
GENERIC_RESOLVE_LIMIT=2000 GENERIC_RESOLVE_TIERS=P2 \
  bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh"

echo "=== Step 5: final auto-trust ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Step 6: P2 blocker summary ==="
bash "$SCRIPT_DIR/run_p2_crawl_blockers.sh"
