#!/usr/bin/env python3
"""Find generic career pages that expose JobPosting JSON-LD."""

from __future__ import annotations

import argparse
import csv
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from crawl_generic_jsonld import fetch_text, job_items, json_ld_payloads


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("targets_csv")
    parser.add_argument("results_csv")
    parser.add_argument("--timeout", type=int, default=8)
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()

    with open(args.targets_csv, newline="", encoding="utf-8") as handle:
        targets = list(csv.DictReader(handle))

    fields = ["site_id", "consolidation_key", "canonical_name", "site_url", "jobposting_count", "error_message"]
    Path(args.results_csv).parent.mkdir(parents=True, exist_ok=True)
    with open(args.results_csv, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()

        def check(target: dict) -> dict:
            error = ""
            count = 0
            try:
                body, _status = fetch_text(target["site_url"], args.timeout)
                count = sum(len(job_items(payload)) for payload in json_ld_payloads(body))
            except Exception as exc:  # noqa: BLE001
                error = f"{type(exc).__name__}: {exc}"[:500]
            return {**{field: target.get(field, "") for field in fields[:4]}, "jobposting_count": count, "error_message": error}

        with ThreadPoolExecutor(max_workers=max(1, args.workers)) as executor:
            futures = [executor.submit(check, target) for target in targets]
            for index, future in enumerate(as_completed(futures), start=1):
                row = future.result()
                writer.writerow(row)
                print(f"[{index}/{len(targets)}] {row['canonical_name']}: {row['jobposting_count']} JobPosting", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
