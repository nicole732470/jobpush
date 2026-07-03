#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/jobpush}"

git -C "$INSTALL_DIR" fetch origin main
git -C "$INSTALL_DIR" pull --ff-only origin main

cd "$INSTALL_DIR"
LOG_FILE="$INSTALL_DIR/logs/zero_credit_site_processing.log" \
  bash db/start_zero_credit_site_processing_loop.sh
