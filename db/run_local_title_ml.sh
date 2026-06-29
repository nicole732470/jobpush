#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
TMP_DIR="$(mktemp -d -t jobpush-local-title-ml.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

"${PSQL[@]}" -qAt -c "COPY (
  SELECT normalized_title, classification_status
  FROM jobpush.job_title_labels
  WHERE rule_version LIKE 'manual%'
    AND classification_status IN ('target','non_target')
) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > "$TMP_DIR/manual_holdout_labels.csv"

cp "$TMP_DIR/manual_holdout_labels.csv" "$TMP_DIR/train_labels.csv"

"${PSQL[@]}" -qAt -c "COPY (
  SELECT normalized_title
  FROM jobpush.job_title_labels
  WHERE classification_status = 'review'
    AND coalesce(rule_version, '') NOT LIKE 'manual%'
) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > "$TMP_DIR/review.csv"

python3 "$REPO_DIR/scripts/train_local_title_classifier.py" \
  "$TMP_DIR/train_labels.csv" "$TMP_DIR/review.csv" \
  "$TMP_DIR/predictions.sql" "$TMP_DIR/metrics.json" \
  --holdout-labels-csv "$TMP_DIR/manual_holdout_labels.csv" \
  --model-version local-title-ml-v3 \
  --variant stem \
  --class-prior balanced \
  --auto-label non_target
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$TMP_DIR/predictions.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT * FROM jobpush.apply_local_job_title_ml('local-title-ml-v3', 10000);"
"${PSQL[@]}" -P pager=off -c \
  "SELECT classification_status, rule_version, count(*) FROM jobpush.job_title_labels GROUP BY 1,2 ORDER BY 1,2;"
