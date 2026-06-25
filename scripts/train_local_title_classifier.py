#!/usr/bin/env python3
"""Train an offline title classifier from manual labels and emit audited SQL.

Standard-library multinomial Naive Bayes keeps deployment dependency-free.
Predictions are eligible only when deterministic 5-fold holdout precision
reaches the configured gate; hard profile rules and manual labels stay above it.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path

MODEL_VERSION = "local-title-ml-v1"
LABELS = ("target", "non_target")


def features(title: str) -> list[str]:
    words = re.findall(r"[a-z0-9+#.]+", title.casefold())
    result = [f"w:{word}" for word in words if len(word) > 1]
    result.extend(f"b:{a}_{b}" for a, b in zip(words, words[1:]))
    return result


def train(rows: list[tuple[str, str]]) -> dict[str, object]:
    counts = {label: Counter() for label in LABELS}
    totals = Counter()
    docs = Counter()
    vocabulary = set()
    for title, label in rows:
        docs[label] += 1
        row_features = features(title)
        counts[label].update(row_features)
        totals[label] += len(row_features)
        vocabulary.update(row_features)
    return {"counts": counts, "totals": totals, "docs": docs, "vocab": vocabulary}


def predict(model: dict[str, object], title: str) -> tuple[str, float, list[str]]:
    counts = model["counts"]
    totals = model["totals"]
    docs = model["docs"]
    vocab = model["vocab"]
    title_features = features(title)
    total_docs = sum(docs.values())
    if total_docs == 0 or any(docs[label] == 0 for label in LABELS):
        return "non_target", 0.5, []
    scores = {}
    for label in LABELS:
        score = math.log((docs[label] + 1) / (total_docs + len(LABELS)))
        denom = totals[label] + max(len(vocab), 1)
        for feature in title_features:
            score += math.log((counts[label][feature] + 1) / denom)
        scores[label] = score
    delta = scores["target"] - scores["non_target"]
    probability_target = 1 / (1 + math.exp(-max(-60, min(60, delta))))
    label = "target" if probability_target >= 0.5 else "non_target"
    confidence = probability_target if label == "target" else 1 - probability_target
    opposite = "non_target" if label == "target" else "target"
    ranked = sorted(
        set(title_features),
        key=lambda feature: (
            (counts[label][feature] + 1) / (totals[label] + max(len(vocab), 1))
            / ((counts[opposite][feature] + 1) / (totals[opposite] + max(len(vocab), 1)))
        ),
        reverse=True,
    )[:5]
    return label, confidence, ranked


def fold_for(title: str) -> int:
    return int(hashlib.sha256(title.encode("utf-8")).hexdigest()[:8], 16) % 5


def choose_threshold(results: list[tuple[str, str, float]], label: str, gate: float, minimum: int) -> tuple[float, float, int]:
    for threshold in (0.995, 0.99, 0.98, 0.95, 0.90, 0.85):
        selected = [row for row in results if row[1] == label and row[2] >= threshold]
        if len(selected) < minimum:
            continue
        precision = sum(actual == label for actual, _, _ in selected) / len(selected)
        if precision >= gate:
            return threshold, precision, len(selected)
    return 1.001, 0.0, 0


def sql_literal(value: object) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("labels_csv")
    parser.add_argument("review_csv")
    parser.add_argument("output_sql")
    parser.add_argument("metrics_json")
    parser.add_argument("--precision-gate", type=float, default=0.98)
    parser.add_argument("--minimum-holdout", type=int, default=10)
    args = parser.parse_args()

    with open(args.labels_csv, newline="", encoding="utf-8") as handle:
        labels = [(row["normalized_title"], row["classification_status"])
                  for row in csv.DictReader(handle)
                  if row["classification_status"] in LABELS]
    with open(args.review_csv, newline="", encoding="utf-8") as handle:
        review = list(csv.DictReader(handle))

    holdout_results = []
    for fold in range(5):
        train_rows = [row for row in labels if fold_for(row[0]) != fold]
        test_rows = [row for row in labels if fold_for(row[0]) == fold]
        model = train(train_rows)
        for title, actual in test_rows:
            predicted, confidence, _ = predict(model, title)
            holdout_results.append((actual, predicted, confidence))

    thresholds = {}
    for label in LABELS:
        threshold, precision, count = choose_threshold(
            holdout_results, label, args.precision_gate, args.minimum_holdout
        )
        thresholds[label] = {"threshold": threshold, "precision": precision, "count": count}

    final_model = train(labels)
    metrics = {
        "model_version": MODEL_VERSION,
        "training_labels": len(labels),
        "class_counts": dict(Counter(label for _, label in labels)),
        "precision_gate": args.precision_gate,
        "thresholds": thresholds,
    }
    Path(args.metrics_json).write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    statements = ["BEGIN;"]
    applied_candidates = 0
    metrics_literal = sql_literal(json.dumps(metrics, separators=(",", ":")))
    for row in review:
        title = row["normalized_title"]
        predicted, confidence, evidence = predict(final_model, title)
        threshold_info = thresholds[predicted]
        if confidence < threshold_info["threshold"]:
            continue
        evidence_sql = "ARRAY[" + ",".join(sql_literal(item) for item in evidence) + "]::text[]"
        statements.append(
            "INSERT INTO jobpush.job_title_ml_classifications ("
            "normalized_title, classification_status, confidence, model_version, "
            "training_label_count, holdout_precision, holdout_threshold, evidence_features, metrics"
            ") VALUES ("
            f"{sql_literal(title)}, {sql_literal(predicted)}, {confidence:.5f}, "
            f"{sql_literal(MODEL_VERSION)}, {len(labels)}, {threshold_info['precision']:.5f}, "
            f"{threshold_info['threshold']:.5f}, {evidence_sql}, {metrics_literal}::jsonb"
            ") ON CONFLICT (normalized_title, model_version) DO UPDATE SET "
            "classification_status=EXCLUDED.classification_status, confidence=EXCLUDED.confidence, "
            "training_label_count=EXCLUDED.training_label_count, "
            "holdout_precision=EXCLUDED.holdout_precision, holdout_threshold=EXCLUDED.holdout_threshold, "
            "evidence_features=EXCLUDED.evidence_features, metrics=EXCLUDED.metrics;"
        )
        applied_candidates += 1
    statements.append("COMMIT;")
    Path(args.output_sql).write_text("\n".join(statements) + "\n", encoding="utf-8")
    print(json.dumps({**metrics, "eligible_review_predictions": applied_candidates}, indent=2))


if __name__ == "__main__":
    main()
