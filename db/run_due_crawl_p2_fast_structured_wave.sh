#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES=(greenhouse smartrecruiters ashby lever paylocity oracle_cloud workable jobvite rippling)

for source_type in "${SOURCES[@]}"; do
  echo "=== P2 fast due crawl source_type=$source_type ==="
  PRIORITY_TIER_FILTER=P2 \
    SOURCE_TYPE_FILTER="$source_type" \
    SKIP_POST_CRAWL_TITLE_ML=1 \
    bash "$SCRIPT_DIR/run_due_crawl_batch.sh" 5 || true
done
