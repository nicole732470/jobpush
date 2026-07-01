#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
python3 scripts/crawl_uber_jobs.py \
  --url 'https://jobs.uber.com/en/jobs/?radius=1000' \
  --output /tmp/uber-jobs.csv \
  --default-market unknown \
  --max-pages 2 \
  --page-size 10
wc -l /tmp/uber-jobs.csv
head -3 /tmp/uber-jobs.csv
