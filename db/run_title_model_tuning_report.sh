#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

OUT_DIR="$REPO_DIR/outputs/title_model_tuning_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"

"${PSQL[@]}" -qAt -c "COPY (
  SELECT normalized_title, classification_status
  FROM jobpush.job_title_labels
  WHERE rule_version LIKE 'manual%'
    AND classification_status IN ('target','non_target')
  ORDER BY normalized_title
) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > "$OUT_DIR/manual_labels.csv"

python3 "$REPO_DIR/scripts/evaluate_title_classifier_variants.py" \
  "$OUT_DIR/manual_labels.csv" \
  "$OUT_DIR/title_model_tuning_report.json" \
  "$OUT_DIR/title_model_tuning_report.csv"

echo "Wrote $OUT_DIR/title_model_tuning_report.json"
echo "Wrote $OUT_DIR/title_model_tuning_report.csv"
