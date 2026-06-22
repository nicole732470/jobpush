#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONSOLIDATION_KEY="apple" SOURCE_TYPE="apple_jobs"
export ADAPTER_NAME="apple-jobs-api" ADAPTER_VERSION="0.1.0"
export ADAPTER_SCRIPT="scripts/crawl_apple_jobs.py"
export COHORT="apple-jobs-pilot" PRIORITY_TIER="P1"
exec "$SCRIPT_DIR/lib/run_structured_adapter_pilot.sh"
