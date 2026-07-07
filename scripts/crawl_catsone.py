#!/usr/bin/env python3
"""Fetch CATS One career boards from their server-rendered job table."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

from market_scope import classify_market_scope


FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: object) -> str:
    return re.sub(r"\s+", " ", html.unescape("" if value is None else str(value))).strip()


def strip_html(value: str) -> str:
    return clean(re.sub(r"<[^>]+>", " ", value))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def fetch_text(url: str) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "text/html"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


ROW_RE = re.compile(
    r'<a\b[^>]*class=["\'][^"\']*table-row[^"\']*["\'][^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>',
    re.I | re.S,
)


def rows_for(body: str, source_url: str, default_market: str) -> list[dict]:
    rows = []
    seen = set()
    for href, block in ROW_RE.findall(body):
        title_match = re.search(r'title-cell[^>]*>(.*?)</div>', block, re.I | re.S)
        cells = re.findall(r'data-cell[^>]*data-label=["\']([^"\']+)["\'][^>]*>(.*?)</div>', block, re.I | re.S)
        data = {clean(label).casefold(): strip_html(value) for label, value in cells}
        title = strip_html(title_match.group(1)) if title_match else ""
        location = data.get("location", "")
        category = data.get("category", "")
        if not title:
            continue
        market_scope = classify_market_scope(location, default_market)
        if market_scope != "US":
            continue
        job_url = urljoin(source_url, clean(href))
        external_id = urlsplit(job_url).path.rstrip("/").split("/")[-1]
        if external_id in seen:
            continue
        seen.add(external_id)
        rows.append({
            "external_job_id": external_id,
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": category,
            "job_url": job_url,
            "description_snippet": clean(f"{category} · {location}"),
            "market_scope": market_scope,
            "posted_text": "",
            "employment_type": "",
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "unknown"), default="unknown")
    args = parser.parse_args()
    started = time.monotonic()
    body, status = fetch_text(args.url)
    rows = rows_for(body, args.url, args.default_market)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({"status": "succeeded", "requests_count": 1, "pages_fetched": 1,
                      "raw_job_count": len(rows), "parsed_job_count": len(rows),
                      "duplicate_count": 0, "last_http_status": status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


def _self_check() -> None:
    sample = '<a class="table-row" href="/careers/1/jobs/2"><div class="data-cell title-cell">QA Analyst</div><div class="data-cell" data-label="Category">IT</div><div class="data-cell" data-label="Location">Chicago, IL</div></a>'
    assert rows_for(sample, "https://acme.catsone.com/careers", "unknown")[0]["title"] == "QA Analyst"


if __name__ == "__main__":
    _self_check()
    raise SystemExit(main())
