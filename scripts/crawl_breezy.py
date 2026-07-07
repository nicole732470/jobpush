#!/usr/bin/env python3
"""Fetch Breezy HR career boards from rendered position cards."""

from __future__ import annotations

import argparse
import csv
import hashlib
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
    r'<li\b[^>]*class=["\'][^"\']*position transition[^"\']*["\'][^>]*>(.*?)</li>\s*</ul>\s*</li>',
    re.I | re.S,
)


def rows_for(body: str, source_url: str, default_market: str) -> list[dict]:
    rows = []
    seen = set()
    for match in CARD_RE.finditer(body):
        block = match.group(1)
        href_match = re.search(r'<a\b[^>]*href=["\']([^"\']+)["\']', block, re.I | re.S)
        title_match = re.search(r'<h2>(.*?)</h2>', block, re.I | re.S)
        dept_match = re.search(r'<li[^>]+class=["\']department["\'][^>]*>.*?<span>(.*?)</span>', block, re.I | re.S)
        type_match = re.search(r'LABEL_POSITION_TYPE_([^%<]+)', block, re.I)
        location_match = list(re.finditer(r'<h2 class=["\']group-header["\'][^>]*>.*?<span>(.*?)</span>', body[:match.start()], re.I | re.S))
        title = strip_html(title_match.group(1)) if title_match else ""
        location = strip_html(location_match[-1].group(1)) if location_match else ""
        category = strip_html(dept_match.group(1)) if dept_match else ""
        employment_type = clean(type_match.group(1).replace("_", " ").title()) if type_match else ""
        if not href_match or not title:
            continue
        market_scope = classify_market_scope(location, default_market)
        if market_scope != "US":
            continue
        job_url = urljoin(source_url, clean(href_match.group(1)))
        external_id = hashlib.sha1(f"{urlsplit(job_url).path}|{location}".encode("utf-8")).hexdigest()[:24]
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
            "description_snippet": clean(f"{category} · {employment_type} · {location}"),
            "market_scope": market_scope,
            "posted_text": "",
            "employment_type": employment_type,
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
    sample = '<h2 class="group-header"><span>Chicago, IL</span></h2><li class="position transition"><ul><li><a href="/p/abc"><h2>Product Manager</h2><li class="department"><span>Product</span></li><span class="polygot">%LABEL_POSITION_TYPE_FULL_TIME%</span></a></li></ul></li>'
    assert rows_for(sample, "https://acme.breezy.hr/", "unknown")[0]["category"] == "Product"


if __name__ == "__main__":
    _self_check()
    raise SystemExit(main())
