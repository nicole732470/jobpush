#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DISCOVERY_LIMIT=350 bash "$SCRIPT_DIR/run_discover_career_sites_p0_p1.sh"
