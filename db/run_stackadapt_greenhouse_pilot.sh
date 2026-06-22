#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONSOLIDATION_KEY="30-1005380" SOURCE_TYPE="greenhouse"
export ADAPTER_NAME="greenhouse-api" ADAPTER_VERSION="0.2.0"
export ADAPTER_SCRIPT="scripts/crawl_greenhouse.py"
export COHORT="stackadapt-greenhouse-pilot" PRIORITY_TIER="P1"
exec "$SCRIPT_DIR/lib/run_structured_adapter_pilot.sh"
