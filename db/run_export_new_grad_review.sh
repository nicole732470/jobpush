#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -f "$SCRIPT_DIR/analysis/export_new_grad_review.sql" >&2
tar -czf /tmp/new_grad_review_export.tgz -C /tmp new_grad_non_target.csv new_grad_review.csv
wc -c /tmp/new_grad_review_export.tgz
sha256sum /tmp/new_grad_review_export.tgz
