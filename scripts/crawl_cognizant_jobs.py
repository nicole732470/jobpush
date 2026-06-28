#!/usr/bin/env python3
"""Fetch Cognizant's paginated US jobs HTML into adapter CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import math
import re
import time
from pathlib import Path
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: object) -> str:
    return re.sub(r"\s+", " ", html.unescape("" if value is None else str(value))).strip()


def strip_tags(value: str) -> str:
    return clean(re.sub(r"<[^>]+>", " ", value))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def fetch(url: str, timeout: int) -> tuple[str, int]:
    request = Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0 Safari/537.36",
        "Accept": "text/html",
        "Accept-Language": "en-US,en;q=0.9",
    })
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "ignore"), response.status


def page_url(raw_url: str, page: int) -> str:
    parsed = urlsplit(raw_url)
    params = {"location": "United States", "radius": "100", "cname": "United States", "ccode": "US", "pagesize": "10"}
    if page > 1:
        params["page"] = str(page)
    return f"{parsed.scheme}://{parsed.netloc}/us-en/jobs?{urlencode(params)}"


def parse_page(body: str, origin: str) -> tuple[int, list[dict[str, str]]]:
    total_match = re.search(r'data-results="(\d+)"', body)
    total = int(total_match.group(1)) if total_match else 0
    rows = []
    for card in re.findall(r'<div class="card card-job" data-id="([^"]+)">(.*?)(?=<div class="card card-job"|</div>\s*</div>\s*<ul class="pagination)', body, re.S):
        external_id, chunk = card
        link = re.search(r'<a class="stretched-link js-view-job" href="([^"]+)">(.*?)</a>', chunk, re.S)
        if not link:
            continue
        meta = [strip_tags(item) for item in re.findall(r'<li class="list-inline-item">\s*(.*?)\s*</li>', chunk, re.S)]
        title = strip_tags(link.group(2))
        href = html.unescape(link.group(1))
        rows.append({
            "external_job_id": clean(external_id),
            "title": title,
            "normalized_title": normalize(title),
            "location": meta[0] if meta else "",
            "category": meta[-1] if len(meta) > 1 else "",
            "job_url": href if href.startswith("http") else f"{origin}{href}",
            "description_snippet": "",
            "market_scope": "US",
            "posted_text": "",
            "employment_type": "",
        })
    return total, rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "unknown"), default="US")
    parser.add_argument("--max-pages", type=int, default=80)
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    started = time.monotonic()
    parsed = urlsplit(args.url)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    rows: dict[str, dict[str, str]] = {}
    requests = 0
    last_status = 0
    total = 1
    pages = 1
    for page in range(1, args.max_pages + 1):
        body, last_status = fetch(page_url(args.url, page), args.timeout)
        requests += 1
        total, page_rows = parse_page(body, origin)
        pages = min(args.max_pages, max(1, math.ceil(total / 10)))
        for row in page_rows:
            rows[row["external_job_id"]] = row
        if page >= pages or not page_rows:
            break

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows.values())

    print(json.dumps({"status": "succeeded", "requests_count": requests,
                      "pages_fetched": requests, "raw_job_count": len(rows),
                      "parsed_job_count": len(rows), "duplicate_count": 0,
                      "last_http_status": last_status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
