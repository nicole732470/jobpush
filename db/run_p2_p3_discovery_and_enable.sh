#!/usr/bin/env bash
# P2/P3 site discovery (Tavily) + zero-credit refinement + structured ATS auto-trust入库.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

P2_LIMIT="${P2_DISCOVERY_LIMIT:-500}"
P3_LIMIT="${P3_DISCOVERY_LIMIT:-500}"
ATS_GUESS_LIMIT="${ATS_GUESS_LIMIT:-1000}"
GENERIC_RESOLVE_LIMIT="${GENERIC_RESOLVE_LIMIT:-1000}"

echo "=== Phase 1: P2 Tavily discovery (limit=$P2_LIMIT) ==="
bash "$SCRIPT_DIR/run_discover_career_sites_p2.sh" "$P2_LIMIT"

echo "=== Phase 2: P3 Tavily discovery (limit=$P3_LIMIT) ==="
bash "$SCRIPT_DIR/run_discover_career_sites_p3.sh" "$P3_LIMIT"

echo "=== Phase 3: Auto-trust structured ATS (post-discovery) ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Phase 4: Zero-credit ATS URL guess P2/P3 (limit=$ATS_GUESS_LIMIT) ==="
ATS_GUESS_TIERS=P2,P3 ATS_GUESS_LIMIT="$ATS_GUESS_LIMIT" \
  bash "$SCRIPT_DIR/run_guess_ats_sites.sh"

echo "=== Phase 5: Auto-trust structured ATS (post-guess) ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Phase 6: Zero-credit generic HTML ATS resolver P2/P3 (limit=$GENERIC_RESOLVE_LIMIT) ==="
GENERIC_RESOLVE_LIMIT="$GENERIC_RESOLVE_LIMIT" GENERIC_RESOLVE_TIERS=P2,P3 \
  bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh"

echo "=== Phase 7: Final auto-trust ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Phase 8: P2/P3 coverage status ==="
bash "$SCRIPT_DIR/run_site_coverage_status.sh"
