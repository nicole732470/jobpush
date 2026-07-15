#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONSOLIDATION_KEY="instawork" SOURCE_TYPE="greenhouse"
export ADAPTER_NAME="greenhouse-api" ADAPTER_VERSION="0.2.0"
export ADAPTER_SCRIPT="scripts/crawl_greenhouse.py"
export COHORT="instawork-greenhouse-pilot" PRIORITY_TIER="P0"
export SCOPE_METHOD="verified_us_only"
exec "$SCRIPT_DIR/lib/run_structured_adapter_pilot.sh"
