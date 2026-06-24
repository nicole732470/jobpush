#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/jobpush}"
source "$INSTALL_DIR/db/lib/connect_rds.sh"

export JOBPUSH_DB_HOST="$RDS_HOST"
export JOBPUSH_DB_PORT="$RDS_PORT"
export JOBPUSH_DB_NAME="$RDS_DB"
export JOBPUSH_DB_USER="$RDS_USER"
export JOBPUSH_DB_PASSWORD="$RDS_PASS"
export JOBPUSH_DB_SSLMODE=require

cd "$INSTALL_DIR/app"
exec "$INSTALL_DIR/.venv-dashboard/bin/streamlit" run dashboard.py
