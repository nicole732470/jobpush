#!/usr/bin/env python3
"""Fetch Trakstar Hire career boards from their rendered listing cards."""

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


CARD_RE = re.compile(
    r'<div\b[^>]*js-careers-page-job-list-item[^>]*data-href=["\']([^"\']+)["\'][^>]*>(.*?)</div>\s*</div>',
    re.I | re.S,
)


def rows_for(body: str, source_url: str, default_market: str) -> list[dict]:
    rows = []
    seen = set()
    for href, block in CARD_RE.findall(body):
        title_match = re.search(r'js-job-list-opening-name[^>]*title=["\']([^"\']+)["\']', block, re.I | re.S)
        title = clean(title_match.group(1)) if title_match else ""
        city = strip_html(" ".join(re.findall(r'meta-job-location-city[^>]*>(.*?)</span>', block, re.I | re.S)))
        state = strip_html(" ".join(re.findall(r'meta-job-location-state[^>]*>(.*?)</span>', block, re.I | re.S)))
        country = strip_html(" ".join(re.findall(r'meta-job-location-country[^>]*>(.*?)</span>', block, re.I | re.S)))
        location = clean(", ".join(piece for piece in [city, state, country] if piece))
        if not title:
            continue
        market_scope = classify_market_scope(location, default_market)
        if market_scope != "US":
            continue
        job_url = urljoin(source_url, clean(href))
        external_id = urlsplit(job_url).path.strip("/").replace("/", "-")
        if external_id in seen:
            continue
        seen.add(external_id)
        rows.append({
            "external_job_id": external_id,
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": "",
            "job_url": job_url,
            "description_snippet": location,
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
    sample = '<div class="js-careers-page-job-list-item" data-href="/jobs/fk0qap/"><h3 class="js-job-list-opening-name" title="Account Director">Account Director</h3><span class="meta-job-location-city">Memphis</span><span class="meta-job-location-state">TN</span><span class="meta-job-location-country">United States</span></div></div>'
    assert rows_for(sample, "https://x.hire.trakstar.com/", "unknown")[0]["location"] == "Memphis, TN, United States"


if __name__ == "__main__":
    _self_check()
    raise SystemExit(main())
