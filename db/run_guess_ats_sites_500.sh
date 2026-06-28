#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATS_GUESS_LIMIT=500 bash "$SCRIPT_DIR/run_guess_ats_sites.sh"
