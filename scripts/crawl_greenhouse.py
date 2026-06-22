#!/usr/bin/env python3
"""Fetch a public Greenhouse board into JobPush's normalized adapter CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: str | None) -> str:
    return re.sub(r"\s+", " ", html.unescape(value or "")).strip()


def strip_html(value: str | None) -> str:
    return clean(re.sub(r"<[^>]+>", " ", html.unescape(value or "")))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def board_token(url: str) -> str:
    parts = [part for part in urlsplit(url).path.split("/") if part]
    if not parts:
        raise ValueError(f"Cannot derive Greenhouse board token from {url}")
    return parts[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    args = ap.parse_args()

    started = time.monotonic()
    endpoint = f"https://boards-api.greenhouse.io/v1/boards/{board_token(args.url)}/jobs?content=true"
    request = Request(endpoint, headers={"User-Agent": "JobPush/0.1", "Accept": "application/json"})
    with urlopen(request, timeout=30) as response:
        status = response.status
        payload = json.load(response)

    rows = []
    for job in payload.get("jobs", []):
        departments = ", ".join(clean(item.get("name")) for item in job.get("departments", []))
        rows.append({
            "external_job_id": str(job["id"]),
            "title": clean(job.get("title")),
            "normalized_title": normalize(job.get("title", "")),
            "location": clean((job.get("location") or {}).get("name")),
            "category": departments,
            "job_url": clean(job.get("absolute_url")),
            "description_snippet": strip_html(job.get("content"))[:1000],
            "market_scope": args.default_market,
            "posted_text": clean(job.get("updated_at")),
            "employment_type": "",
        })

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({"status": "succeeded", "requests_count": 1, "pages_fetched": 1,
                      "raw_job_count": len(rows), "parsed_job_count": len(rows),
                      "duplicate_count": 0, "last_http_status": status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
