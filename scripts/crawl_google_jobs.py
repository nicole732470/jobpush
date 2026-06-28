#!/usr/bin/env python3
"""Fetch Google Careers US result pages into normalized adapter CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import urlencode, urlsplit
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


def fetch(url: str, timeout: int) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html"})
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "ignore"), response.status


def page_url(raw_url: str, page: int) -> str:
    parsed = urlsplit(raw_url)
    return f"{parsed.scheme}://{parsed.netloc}{parsed.path}?{urlencode({'location': 'United States', 'page': page})}"


def parse_jobs(body: str) -> list[dict[str, str]]:
    starts = list(re.finditer(r'\["(?P<id>\d{8,})","(?P<title>(?:\\.|[^"\\])+)","(?P<url>https://www\.google\.com/about/careers/applications/signin\?jobId(?:\\.|[^"\\])*)"', body))
    rows = []
    for idx, match in enumerate(starts):
        chunk = body[match.start(): starts[idx + 1].start() if idx + 1 < len(starts) else match.start() + 30000]
        title = clean(json.loads(f'"{match.group("title")}"'))
        job_url = clean(json.loads(f'"{match.group("url")}"')).replace(r"\u003d", "=").replace(r"\u0026", "&")
        locations = []
        for loc in re.findall(r'\["([^"]+?,\s*[A-Z]{2},\s*USA)"', chunk):
            if loc not in locations:
                locations.append(loc)
        category_match = re.search(r'"(Google(?: Cloud| Ads| DeepMind| Fiber)?|YouTube)"', chunk)
        rows.append({
            "external_job_id": match.group("id"),
            "title": title,
            "normalized_title": normalize(title),
            "location": "; ".join(locations),
            "category": clean(category_match.group(1) if category_match else "Google"),
            "job_url": job_url,
            "description_snippet": strip_html(chunk[:4000])[:1000],
            "market_scope": "US",
            "posted_text": "",
            "employment_type": "",
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "unknown"), default="US")
    parser.add_argument("--max-pages", type=int, default=120)
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    started = time.monotonic()
    rows: dict[str, dict[str, str]] = {}
    requests = 0
    last_status = 0
    for page in range(1, args.max_pages + 1):
        body, last_status = fetch(page_url(args.url, page), args.timeout)
        requests += 1
        page_rows = parse_jobs(body)
        new_count = 0
        for row in page_rows:
            new_count += row["external_job_id"] not in rows
            rows[row["external_job_id"]] = row
        if not page_rows or new_count == 0:
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
