#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONSOLIDATION_KEY="13-2624428" SOURCE_TYPE="oracle_cloud"
export ADAPTER_NAME="oracle-cloud-rest" ADAPTER_VERSION="0.1.0"
export ADAPTER_SCRIPT="scripts/crawl_oracle_cloud.py"
export COHORT="jpmorgan-oracle-pilot" PRIORITY_TIER="P0"
export SCOPE_METHOD="server_filter"
exec "$SCRIPT_DIR/lib/run_structured_adapter_pilot.sh"
