#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONSOLIDATION_KEY="77-0080465" SOURCE_TYPE="icims"
export ADAPTER_NAME="icims-html" ADAPTER_VERSION="0.3.0"
export ADAPTER_SCRIPT="scripts/crawl_icims.py"
export COHORT="here-icims-pilot" PRIORITY_TIER="P0"
export SCOPE_METHOD="server_filter"
exec "$SCRIPT_DIR/lib/run_structured_adapter_pilot.sh"
