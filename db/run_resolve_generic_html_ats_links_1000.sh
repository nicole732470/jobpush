#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERIC_RESOLVE_LIMIT=1000 bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh"
