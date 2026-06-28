#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
TMP_DIR="$(mktemp -d -t jobpush-local-title-ml-probe.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

"${PSQL[@]}" -qAt -c "COPY (
  SELECT normalized_title, classification_status
  FROM jobpush.job_title_labels
  WHERE rule_version LIKE 'manual%'
    AND classification_status IN ('target','non_target')
) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > "$TMP_DIR/manual_holdout_labels.csv"

"${PSQL[@]}" -qAt -c "COPY (
  WITH manual_labels AS (
    SELECT normalized_title, classification_status, 'manual' AS training_source
    FROM jobpush.job_title_labels
    WHERE rule_version LIKE 'manual%'
      AND classification_status IN ('target','non_target')
  ), trusted_rule_labels AS (
    SELECT normalized_title, classification_status, training_source
    FROM (
      SELECT
        label.normalized_title,
        label.classification_status,
        split_part(COALESCE(label.decision_reason, 'unknown'), ':', 1) AS training_source,
        row_number() OVER (
          PARTITION BY split_part(COALESCE(label.decision_reason, 'unknown'), ':', 1)
          ORDER BY COALESCE(catalog.active_posting_count, 0) DESC, label.normalized_title
        ) AS source_rank
      FROM jobpush.job_title_labels label
      LEFT JOIN jobpush.job_title_catalog catalog USING (normalized_title)
      WHERE label.rule_version = 'profile-title-rules-v2'
        AND label.classification_status = 'non_target'
        AND label.labeled_by = 'system:profile-title-rules-v2'
        AND NOT EXISTS (
          SELECT 1 FROM manual_labels manual
          WHERE manual.normalized_title = label.normalized_title
        )
    ) ranked
    WHERE source_rank <= 75
  )
  SELECT normalized_title, classification_status FROM manual_labels
  UNION ALL
  SELECT normalized_title, classification_status FROM trusted_rule_labels
) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > "$TMP_DIR/train_labels.csv"

"${PSQL[@]}" -qAt -c "COPY (
  SELECT normalized_title
  FROM jobpush.job_title_labels
  WHERE classification_status = 'review'
    AND coalesce(rule_version, '') NOT LIKE 'manual%'
) TO STDOUT WITH (FORMAT CSV, HEADER TRUE)" > "$TMP_DIR/review.csv"

for variant in baseline exclusive; do
  echo "=== weak-supervision challenger probe variant=$variant minimum_holdout=1 ==="
  python3 "$REPO_DIR/scripts/train_local_title_classifier.py" \
    "$TMP_DIR/train_labels.csv" "$TMP_DIR/review.csv" \
    "$TMP_DIR/predictions-$variant.sql" "$TMP_DIR/metrics-$variant.json" \
    --holdout-labels-csv "$TMP_DIR/manual_holdout_labels.csv" \
    --model-version "local-title-ml-v2-probe-$variant" \
    --variant "$variant" \
    --class-prior balanced \
    --auto-label non_target \
    --minimum-holdout 1
done
