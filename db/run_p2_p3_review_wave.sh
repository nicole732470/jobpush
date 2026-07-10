#!/usr/bin/env bash
# P2/P3 zero-credit review wave: auto-trust structured ATS, ATS guess, generic resolver.
# No Tavily credits. Generic HTML leftovers stay in career_site_review_workbench for manual review.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ATS_GUESS_LIMIT="${ATS_GUESS_LIMIT:-1500}"
GENERIC_RESOLVE_LIMIT="${GENERIC_RESOLVE_LIMIT:-1500}"

echo "=== Before: P2/P3 backlog ==="
bash "$SCRIPT_DIR/run_p2_p3_review_backlog.sh"

echo "=== Phase 1: Auto-trust structured ATS (P0-P3) ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Phase 2: Zero-credit ATS URL guess (P2/P3, limit=$ATS_GUESS_LIMIT) ==="
ATS_GUESS_TIERS=P2,P3 ATS_GUESS_LIMIT="$ATS_GUESS_LIMIT" \
  bash "$SCRIPT_DIR/run_guess_ats_sites.sh"

echo "=== Phase 3: Auto-trust after ATS guess ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Phase 4: Zero-credit generic HTML hidden-ATS resolver (P2/P3, limit=$GENERIC_RESOLVE_LIMIT) ==="
GENERIC_RESOLVE_LIMIT="$GENERIC_RESOLVE_LIMIT" GENERIC_RESOLVE_TIERS=P2,P3 \
  bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh"

echo "=== Phase 5: Final auto-trust ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== After: P2/P3 backlog ==="
bash "$SCRIPT_DIR/run_p2_p3_review_backlog.sh"
