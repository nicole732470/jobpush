#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERIC_RESOLVE_TIERS=P2 GENERIC_RESOLVE_RETRY=1 GENERIC_RESOLVE_LIMIT=200 GENERIC_RESOLVE_ROUNDS=1 \
  bash "$SCRIPT_DIR/run_generic_resolver_wave.sh"
