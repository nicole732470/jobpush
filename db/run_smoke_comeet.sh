#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHONPATH="$REPO_DIR/scripts" python3 "$REPO_DIR/scripts/crawl_comeet.py" \
  --url 'https://www.comeet.com/jobs/careersapi-sandbox/E5.007' \
  --output /tmp/comeet-sandbox.csv \
  --default-market US
wc -l /tmp/comeet-sandbox.csv
head -3 /tmp/comeet-sandbox.csv
