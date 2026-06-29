#!/usr/bin/env python3
"""Train an offline title classifier from audited labels and emit SQL.

Standard-library multinomial Naive Bayes keeps deployment dependency-free.
Predictions are eligible only when deterministic 5-fold holdout precision
reaches the configured gate; hard profile rules and manual labels stay above it.

Production uses manual labels as the holdout/evaluation truth set. Training can
also include capped trusted rule labels as weak supervision, but thresholds are
never selected from weak-label performance.
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

MODEL_VERSION = "local-title-ml-v2"
LABELS = ("target", "non_target")
GENERIC_EVIDENCE_TERMS = {
    "associate", "manager", "analyst", "engineer", "specialist", "consultant",
    "operations", "business", "product", "software", "data", "systems",
    "technical", "technology", "program", "project", "development", "sales",
    "service", "services", "support", "customer", "client", "staff", "team",
    "part", "time", "full", "shift", "remote", "hybrid", "intern", "internship",
}


def stem(word: str) -> str:
    for suffix in (
        "ization", "ational", "iveness", "fulness", "ments", "ment", "tion",
        "ing", "ics", "ers", "ies", "ed", "er", "or", "s",
    ):
        if len(word) - len(suffix) >= 4 and word.endswith(suffix):
            return word[: -len(suffix)]
    return word


def features(title: str, variant: str = "baseline") -> list[str]:
    words = re.findall(r"[a-z0-9+#.]+", title.casefold())
    result = [f"w:{word}" for word in words if len(word) > 1]
    result.extend(f"b:{a}_{b}" for a, b in zip(words, words[1:]))
    if variant in {"stem", "stem_char", "exclusive"}:
        result.extend(f"s:{stem(word)}" for word in words if len(word) > 2)
    if variant in {"char", "stem_char"}:
        for word in words:
            if len(word) <= 3:
                continue
            compact = f"^{word}$"
            for size in (3, 4):
                result.extend(
                    f"c{size}:{compact[index:index + size]}"
                    for index in range(0, len(compact) - size + 1)
                )
    return result


def train(rows: list[tuple[str, str]], variant: str, class_prior: str) -> dict[str, object]:
    counts = {label: Counter() for label in LABELS}
    totals = Counter()
    docs = Counter()
    vocabulary = set()
    for title, label in rows:
        docs[label] += 1
        row_features = features(title, variant)
        counts[label].update(row_features)
        totals[label] += len(row_features)
        vocabulary.update(row_features)
    return {
        "counts": counts,
        "totals": totals,
        "docs": docs,
        "vocab": vocabulary,
        "variant": variant,
        "class_prior": class_prior,
    }


def predict(model: dict[str, object], title: str) -> tuple[str, float, list[str]]:
    counts = model["counts"]
    totals = model["totals"]
    docs = model["docs"]
    vocab = model["vocab"]
    variant = str(model.get("variant") or "baseline")
    class_prior = str(model.get("class_prior") or "observed")
    title_features = features(title, variant)
    total_docs = sum(docs.values())
    if total_docs == 0 or any(docs[label] == 0 for label in LABELS):
        return "non_target", 0.5, []

    if variant == "exclusive":
        unique_features = set(title_features)
        non_target_signals = [
            feature for feature in unique_features
            if is_specific_exclusive_feature(feature, counts)
        ]
        target_signals = [
            feature for feature in unique_features
            if counts["target"][feature] >= 2 and counts["non_target"][feature] == 0
        ]
        if non_target_signals and not target_signals:
            ranked = sorted(
                non_target_signals,
                key=lambda feature: (counts["non_target"][feature], len(feature)),
                reverse=True,
            )[:5]
            max_count = counts["non_target"][ranked[0]]
            confidence = 0.995 if max_count >= 5 else 0.99
            return "non_target", confidence, ranked
        if target_signals and not non_target_signals:
            ranked = sorted(
                target_signals,
                key=lambda feature: (counts["target"][feature], len(feature)),
                reverse=True,
            )[:5]
            max_count = counts["target"][ranked[0]]
            confidence = 0.995 if max_count >= 5 else 0.99
            return "target", confidence, ranked
        return "non_target", 0.5, []
    scores = {}
    for label in LABELS:
        if class_prior == "balanced":
            score = math.log(1 / len(LABELS))
        else:
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


def is_specific_exclusive_feature(feature: str, counts: dict[str, Counter]) -> bool:
    if ":" not in feature:
        return False
    prefix, value = feature.split(":", 1)
    pieces = value.split("_")
    if any(piece in GENERIC_EVIDENCE_TERMS for piece in pieces):
        return False
    non_target_count = counts["non_target"][feature]
    target_count = counts["target"][feature]
    if target_count != 0:
        return False
    if prefix == "b":
        return non_target_count >= 4
    if prefix in {"w", "s"}:
        return non_target_count >= 8 and len(value) >= 5
    return False


def choose_threshold(results: list[tuple[str, str, float]], label: str, gate: float, minimum: int) -> tuple[float, float, int]:
    best = (1.001, 0.0, 0)
    for threshold in (0.995, 0.99, 0.98, 0.95, 0.90, 0.85):
        selected = [row for row in results if row[1] == label and row[2] >= threshold]
        if len(selected) < minimum:
            continue
        precision = sum(actual == label for actual, _, _ in selected) / len(selected)
        if precision >= gate:
            best = (threshold, precision, len(selected))
    return best


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
    parser.add_argument("--holdout-labels-csv")
    parser.add_argument("--model-version", default=MODEL_VERSION)
    parser.add_argument("--variant", choices=("baseline", "stem", "char", "stem_char", "exclusive"), default="baseline")
    parser.add_argument("--class-prior", choices=("observed", "balanced"), default="observed")
    parser.add_argument("--auto-label", choices=LABELS, action="append")
    parser.add_argument("--precision-gate", type=float, default=0.98)
    parser.add_argument("--minimum-holdout", type=int, default=10)
    args = parser.parse_args()
    auto_labels = args.auto_label or ["non_target"]

    with open(args.labels_csv, newline="", encoding="utf-8") as handle:
        labels = [(row["normalized_title"], row["classification_status"])
                  for row in csv.DictReader(handle)
                  if row["classification_status"] in LABELS]
    holdout_path = args.holdout_labels_csv or args.labels_csv
    with open(holdout_path, newline="", encoding="utf-8") as handle:
        holdout_labels = [(row["normalized_title"], row["classification_status"])
                          for row in csv.DictReader(handle)
                          if row["classification_status"] in LABELS]
    with open(args.review_csv, newline="", encoding="utf-8") as handle:
        review = list(csv.DictReader(handle))

    holdout_results = []
    for fold in range(5):
        train_rows = [row for row in labels if fold_for(row[0]) != fold]
        test_rows = [row for row in holdout_labels if fold_for(row[0]) == fold]
        model = train(train_rows, args.variant, args.class_prior)
        for title, actual in test_rows:
            predicted, confidence, _ = predict(model, title)
            holdout_results.append((actual, predicted, confidence))

    thresholds = {}
    for label in LABELS:
        threshold, precision, count = choose_threshold(
            holdout_results, label, args.precision_gate, args.minimum_holdout
        )
        thresholds[label] = {"threshold": threshold, "precision": precision, "count": count}

    final_model = train(labels, args.variant, args.class_prior)
    metrics = {
        "model_version": args.model_version,
        "variant": args.variant,
        "class_prior": args.class_prior,
        "training_labels": len(labels),
        "holdout_labels": len(holdout_labels),
        "class_counts": dict(Counter(label for _, label in labels)),
        "holdout_class_counts": dict(Counter(label for _, label in holdout_labels)),
        "precision_gate": args.precision_gate,
        "auto_labels": auto_labels,
        "thresholds": thresholds,
    }
    Path(args.metrics_json).write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    statements = ["BEGIN;"]
    applied_candidates = 0
    metrics_literal = sql_literal(json.dumps(metrics, separators=(",", ":")))
    for row in review:
        title = row["normalized_title"]
        predicted, confidence, evidence = predict(final_model, title)
        if predicted not in auto_labels:
            continue
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
            f"{sql_literal(args.model_version)}, {len(labels)}, {threshold_info['precision']:.5f}, "
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
