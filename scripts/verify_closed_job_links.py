#!/usr/bin/env python3
"""Confirm that missing crawl results are truly closed at their job URLs."""

from __future__ import annotations

import argparse
import csv
import json
import re
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


INACTIVE_PAGE = re.compile(
    r"job (?:is )?no longer available|job posting (?:is )?(?:no longer available|expired|closed)"
    r"|(?:this |the )?(?:job|position|posting) (?:has been )?(?:filled|removed|closed|expired)"
    r"|no longer accepting applications|job not found|couldn['’]?t find this job",
    re.IGNORECASE,
)


def is_confirmed_closed(row: dict[str, str], timeout: int) -> bool:
    request = Request(row["job_url"], headers={"User-Agent": "JobPush/1.0 closure-verifier"})
    try:
        with urlopen(request, timeout=timeout) as response:
            body = response.read(1_000_000).decode(
                response.headers.get_content_charset() or "utf-8", errors="replace"
            )
        return bool(INACTIVE_PAGE.search(body))
    except HTTPError as exc:
        return exc.code in (404, 410)
    except (URLError, TimeoutError, OSError):
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_csv", type=Path)
    parser.add_argument("output_csv", type=Path)
    parser.add_argument("--max-candidates", type=int, default=100)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=15)
    args = parser.parse_args()

    with args.input_csv.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))

    confirmed: list[dict[str, str]] = []
    if len(rows) <= args.max_candidates:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            results = pool.map(lambda row: is_confirmed_closed(row, args.timeout), rows)
            confirmed = [row for row, closed in zip(rows, results) if closed]

    with args.output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["external_job_id"])
        writer.writeheader()
        writer.writerows({"external_job_id": row["external_job_id"]} for row in confirmed)

    print(json.dumps({
        "candidates": len(rows),
        "confirmed_closed": len(confirmed),
        "deferred": len(rows) > args.max_candidates,
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
