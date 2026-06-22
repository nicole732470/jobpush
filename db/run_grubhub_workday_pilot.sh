#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONSOLIDATION_KEY="26-1328194" SOURCE_TYPE="workday"
export ADAPTER_NAME="workday-cxs" ADAPTER_VERSION="0.1.0"
export ADAPTER_SCRIPT="scripts/crawl_workday.py"
export COHORT="grubhub-workday-pilot" PRIORITY_TIER="P0"
exec "$SCRIPT_DIR/lib/run_structured_adapter_pilot.sh"
