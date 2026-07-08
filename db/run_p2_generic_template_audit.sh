#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERIC_TEMPLATE_TIERS=P2 bash "$SCRIPT_DIR/run_generic_blocker_template_audit.sh"
