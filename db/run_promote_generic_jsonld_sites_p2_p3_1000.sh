#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERIC_JSONLD_TIERS=P2,P3 GENERIC_JSONLD_LIMIT=1000 bash "$SCRIPT_DIR/run_promote_generic_jsonld_sites_1000.sh"
