#!/usr/bin/env python3
"""Evaluate local job-title classifier feature variants without applying them.

This script is intentionally dependency-free. It uses the same Naive Bayes
classifier family as production and compares feature sets under deterministic
five-fold holdout. It is a tuning report, not a deployment step.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from collections import Counter
from pathlib import Path

LABELS = ("target", "non_target")
THRESHOLDS = (0.995, 0.99, 0.98, 0.95, 0.90, 0.85, 0.80)


def stem(word: str) -> str:
    for suffix in ("ization", "ational", "iveness", "fulness", "ments", "ment", "tion", "ing", "ics", "ers", "ies", "ed", "er", "or", "s"):
        if len(word) - len(suffix) >= 4 and word.endswith(suffix):
            return word[: -len(suffix)]
    return word


def feature_list(title: str, variant: str) -> list[str]:
    words = re.findall(r"[a-z0-9+#.]+", title.casefold())
    result = [f"w:{word}" for word in words if len(word) > 1]
    result.extend(f"b:{a}_{b}" for a, b in zip(words, words[1:]))
    if variant in {"stem", "stem_char"}:
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


def train(rows: list[tuple[str, str]], variant: str) -> dict[str, object]:
    counts = {label: Counter() for label in LABELS}
    totals = Counter()
    docs = Counter()
    vocabulary = set()
    for title, label in rows:
        docs[label] += 1
        row_features = feature_list(title, variant)
        counts[label].update(row_features)
        totals[label] += len(row_features)
        vocabulary.update(row_features)
    return {"counts": counts, "totals": totals, "docs": docs, "vocab": vocabulary, "variant": variant}


def predict(model: dict[str, object], title: str) -> tuple[str, float]:
    counts = model["counts"]
    totals = model["totals"]
    docs = model["docs"]
    vocab = model["vocab"]
    variant = str(model["variant"])
    total_docs = sum(docs.values())
    if total_docs == 0 or any(docs[label] == 0 for label in LABELS):
        return "non_target", 0.5
    scores = {}
    for label in LABELS:
        score = math.log((docs[label] + 1) / (total_docs + len(LABELS)))
        denom = totals[label] + max(len(vocab), 1)
        for feature in feature_list(title, variant):
            score += math.log((counts[label][feature] + 1) / denom)
        scores[label] = score
    delta = scores["target"] - scores["non_target"]
    probability_target = 1 / (1 + math.exp(-max(-60, min(60, delta))))
    label = "target" if probability_target >= 0.5 else "non_target"
    return label, probability_target if label == "target" else 1 - probability_target


def fold_for(title: str) -> int:
    return int(hashlib.sha256(title.encode("utf-8")).hexdigest()[:8], 16) % 5


def metrics_for(results: list[tuple[str, str, float]], label: str, threshold: float) -> dict[str, object]:
    selected = [row for row in results if row[1] == label and row[2] >= threshold]
    true_positive = sum(actual == label for actual, _, _ in selected)
    actual_total = sum(actual == label for actual, _, _ in results)
    precision = true_positive / len(selected) if selected else None
    recall = true_positive / actual_total if actual_total else None
    return {
        "label": label,
        "threshold": threshold,
        "selected": len(selected),
        "precision": precision,
        "recall": recall,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("labels_csv")
    parser.add_argument("output_json")
    parser.add_argument("output_csv")
    args = parser.parse_args()

    with open(args.labels_csv, newline="", encoding="utf-8") as handle:
        rows = [
            (row["normalized_title"], row["classification_status"])
            for row in csv.DictReader(handle)
            if row["classification_status"] in LABELS
        ]

    report = {
        "training_labels": len(rows),
        "class_counts": dict(Counter(label for _, label in rows)),
        "variants": [],
    }
    csv_rows = []
    for variant in ("baseline", "stem", "char", "stem_char"):
        holdout = []
        for fold in range(5):
            train_rows = [row for row in rows if fold_for(row[0]) != fold]
            test_rows = [row for row in rows if fold_for(row[0]) == fold]
            model = train(train_rows, variant)
            for title, actual in test_rows:
                predicted, confidence = predict(model, title)
                holdout.append((actual, predicted, confidence))
        variant_rows = []
        for label in LABELS:
            for threshold in THRESHOLDS:
                row = {"variant": variant, **metrics_for(holdout, label, threshold)}
                variant_rows.append(row)
                csv_rows.append(row)
        report["variants"].append({"variant": variant, "metrics": variant_rows})

    Path(args.output_json).write_text(json.dumps(report, indent=2), encoding="utf-8")
    with open(args.output_csv, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["variant", "label", "threshold", "selected", "precision", "recall"])
        writer.writeheader()
        writer.writerows(csv_rows)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
