#!/usr/bin/env bash
# Re-drain P2/P3 generic backlog with resolver v2 (same-site hop + iframe/embeds).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GENERIC_RESOLVE_ROUNDS="${GENERIC_RESOLVE_ROUNDS:-8}"
export GENERIC_RESOLVE_LIMIT="${GENERIC_RESOLVE_LIMIT:-1500}"
export GENERIC_RESOLVE_TIERS="${GENERIC_RESOLVE_TIERS:-P2,P3}"
export GENERIC_RESOLVE_RETRY="${GENERIC_RESOLVE_RETRY:-0}"
export ATS_GUESS_LIMIT="${ATS_GUESS_LIMIT:-2000}"
bash "$SCRIPT_DIR/run_p2_p3_generic_ats_drain_wave.sh"
