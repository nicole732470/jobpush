#!/usr/bin/env python3
"""Fetch Amazon Jobs US search JSON into JobPush's normalized adapter CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import math
import re
import time
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen


FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: object) -> str:
    return re.sub(r"\s+", " ", html.unescape("" if value is None else str(value))).strip()


def strip_html(value: object) -> str:
    return clean(re.sub(r"<[^>]+>", " ", clean(value)))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def search_url(raw_url: str, offset: int, limit: int) -> str:
    split = urlsplit(raw_url)
    path = split.path.rstrip("/")
    if not path.endswith(".json"):
        path = f"{path}.json"
    params = dict(parse_qsl(split.query, keep_blank_values=True))
    params.update({
        "offset": str(offset),
        "result_limit": str(limit),
        "country": "USA",
        "loc_query": params.get("loc_query") or "United States",
    })
    return urlunsplit((split.scheme, split.netloc, path, urlencode(params), ""))


def fetch(url: str, timeout: int) -> tuple[dict, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "application/json"})
    with urlopen(request, timeout=timeout) as response:
        return json.load(response), response.status


def row_from_job(job: dict, origin: str) -> dict[str, str]:
    external_id = clean(job.get("id_icims") or job.get("id"))
    path = clean(job.get("job_path"))
    job_url = f"{origin}{path}" if path.startswith("/") else clean(job.get("url_next_step"))
    location = clean(job.get("location") or job.get("normalized_location"))
    return {
        "external_job_id": external_id,
        "title": clean(job.get("title")),
        "normalized_title": normalize(clean(job.get("title"))),
        "location": location,
        "category": clean(job.get("job_category") or job.get("job_family") or job.get("business_category")),
        "job_url": job_url,
        "description_snippet": strip_html(job.get("description_short") or job.get("description"))[:1000],
        "market_scope": "US" if clean(job.get("country_code")) == "USA" else "non-US",
        "posted_text": clean(job.get("posted_date") or job.get("updated_time")),
        "employment_type": clean(job.get("job_schedule_type")),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "unknown"), default="unknown")
    ap.add_argument("--page-size", type=int, default=100)
    ap.add_argument("--max-pages", type=int, default=120)
    ap.add_argument("--timeout", type=int, default=30)
    args = ap.parse_args()

    started = time.monotonic()
    split = urlsplit(args.url)
    origin = f"{split.scheme}://{split.netloc}"

    rows: dict[str, dict[str, str]] = {}
    requests_count = 0
    last_status = 0
    total = 1
    page = 0
    while page < args.max_pages and page * args.page_size < total:
        payload, last_status = fetch(search_url(args.url, page * args.page_size, args.page_size), args.timeout)
        requests_count += 1
        total = int(payload.get("hits") or 0)
        jobs = payload.get("jobs") or []
        for job in jobs:
            if clean(job.get("country_code")) != "USA":
                continue
            row = row_from_job(job, origin)
            if row["external_job_id"] and row["title"]:
                rows[row["external_job_id"]] = row
        if not jobs:
            break
        page += 1

    raw_count = min(total, args.max_pages * args.page_size)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows.values())

    print(json.dumps({"status": "succeeded", "requests_count": requests_count,
                      "pages_fetched": requests_count, "raw_job_count": raw_count,
                      "parsed_job_count": len(rows), "duplicate_count": raw_count - len(rows),
                      "last_http_status": last_status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
