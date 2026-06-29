#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATS_GUESS_TIERS=P2,P3 ATS_GUESS_LIMIT=1000 bash "$SCRIPT_DIR/run_guess_ats_sites.sh"
