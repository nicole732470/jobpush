#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> P2/P3 structured remainder wave (canonicalize + auto-trust + retry failed jsonld)"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/ops/p2_p3_structured_remainder_wave.sql"
