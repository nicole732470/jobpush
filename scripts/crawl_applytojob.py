#!/usr/bin/env python3
"""Fetch ApplyToJob/JazzHR career pages from their server-rendered job list."""

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


ITEM_START_RE = re.compile(r'<li\b[^>]*class=["\'][^"\']*list-group-item[^"\']*["\'][^>]*>', re.I)


def job_id_for(job_url: str, location: str) -> str:
    parts = [part for part in urlsplit(job_url).path.split("/") if part]
    if len(parts) >= 2 and parts[0] == "apply":
        return parts[1]
    return hashlib.sha1(f"{urlsplit(job_url).path}|{location}".encode("utf-8")).hexdigest()[:24]


def rows_for(body: str, source_url: str, default_market: str) -> list[dict]:
    rows = []
    seen = set()
    current_category = ""
    starts = [match.start() for match in ITEM_START_RE.finditer(body)]
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else len(body)
        item = body[start:end]
        department_match = re.search(r'class=["\'][^"\']*department-heading[^"\']*["\'][\s\S]*?<h\d[^>]*>(.*?)</h\d>', item, re.I)
        if department_match:
            current_category = strip_html(department_match.group(1)).rstrip("\xa0").strip()

        link_match = re.search(r'<a\b[^>]*href=["\']([^"\']*/apply/[^"\']+)["\'][^>]*>(.*?)</a>', item, re.I | re.S)
        if not link_match:
            continue
        job_url = urljoin(source_url, clean(link_match.group(1)))
        title = strip_html(link_match.group(2))
        if not title or "/apply/" not in job_url:
            continue

        location = ""
        details_match = re.search(r'<ul\b[^>]*class=["\'][^"\']*list-inline[^"\']*["\'][^>]*>(.*?)</ul>', item, re.I | re.S)
        if details_match:
            details = [strip_html(part) for part in re.findall(r'<li\b[^>]*>(.*?)</li>', details_match.group(1), re.I | re.S)]
            details = [part for part in details if part]
            location = details[0] if details else ""
            if not current_category and len(details) > 1:
                current_category = details[1]

        market_scope = classify_market_scope(location, default_market)
        if market_scope != "US":
            continue
        external_id = job_id_for(job_url, location)
        if external_id in seen:
            continue
        seen.add(external_id)
        rows.append({
            "external_job_id": external_id,
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": current_category,
            "job_url": job_url,
            "description_snippet": clean(f"{current_category} · {location}"),
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
    sample = '''<li class="list-group-item"><div class="department-heading"><h3>Product</h3></div>
    <h3 class="list-group-item-heading"><a href="https://acme.applytojob.com/apply/abc123/Product-Manager">Product Manager</a></h3>
    <ul class="list-inline list-group-item-text"><li><i></i>Chicago, IL</li></ul></li>'''
    row = rows_for(sample, "https://acme.applytojob.com/apply", "unknown")[0]
    assert row["external_job_id"] == "abc123"
    assert row["category"] == "Product"
    assert row["market_scope"] == "US"


if __name__ == "__main__":
    _self_check()
    raise SystemExit(main())
