#!/usr/bin/env python3
"""Fetch JobScore career pages from their stable public HTML list."""

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


def clean(value: str | None) -> str:
    return re.sub(r"\s+", " ", html.unescape(value or "")).strip()


def strip_html(value: str | None) -> str:
    return clean(re.sub(r"<[^>]+>", " ", value or ""))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def fetch_text(url: str) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "text/html"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


def external_id(job_url: str) -> str:
    token = urlsplit(job_url).path.rstrip("/").split("/")[-1]
    return token or normalize(job_url)[:64]


ITEM_OPEN_RE = re.compile(
    r"<div[^>]+class=[\"'][^\"']*js-job-list-item[^\"']*[\"'][^>]+data-url=[\"']([^\"']+)[\"'][^>]*>",
    re.I | re.S,
)
DEPARTMENT_RE = re.compile(r"js-job-department[^>]*>(.*?)</div>", re.I | re.S)


def parse_rows(body: str, source_url: str, default_market: str) -> list[dict]:
    rows: list[dict] = []
    seen: set[str] = set()
    matches = list(ITEM_OPEN_RE.finditer(body))
    for index, match in enumerate(matches):
        href = match.group(1)
        end = matches[index + 1].start() if index + 1 < len(matches) else match.end() + 2200
        job_block = body[match.start():end]
        dept_matches = list(DEPARTMENT_RE.finditer(body[max(0, match.start() - 2500):match.start()]))
        department = strip_html(dept_matches[-1].group(1)) if dept_matches else ""
        title_match = re.search(r"js-job-title[^>]*>.*?<a\b[^>]*>(.*?)</a>", job_block, re.I | re.S)
        location_match = re.search(r"js-job-location[^>]*>(.*?)</span>", job_block, re.I | re.S)
        title = strip_html(title_match.group(1)) if title_match else ""
        location = strip_html(location_match.group(1)) if location_match else ""
        if not title or re.search(r"\bgeneral application\b", title, re.I):
            continue
        market_scope = classify_market_scope(location, default_market)
        if market_scope != "US":
            continue
        job_url = urljoin(source_url, clean(href))
        row_id = external_id(job_url)
        if row_id in seen:
            continue
        seen.add(row_id)
        rows.append({
            "external_job_id": row_id,
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": department,
            "job_url": job_url,
            "description_snippet": clean(f"{department} · {location}"),
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
    rows = parse_rows(body, args.url, args.default_market)

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({"status": "succeeded", "requests_count": 1,
                      "pages_fetched": 1, "raw_job_count": len(rows),
                      "parsed_job_count": len(rows), "duplicate_count": 0,
                      "last_http_status": status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


def _self_check() -> None:
    html_sample = """
    <div class='js-job-departament-container'><div class='js-job-department'>Product</div>
    <div class="js-row js-job-list-item" data-url="/careers/acme/jobs/product-manager-a1">
    <span class="js-job-title"><a href="/careers/acme/jobs/product-manager-a1">Product Manager</a></span>
    <span class="js-job-location">Chicago, IL</span></div></div>
    """
    rows = parse_rows(html_sample, "https://www.jobscore.com/careers/acme", "unknown")
    assert rows[0]["title"] == "Product Manager"
    assert rows[0]["category"] == "Product"
    assert rows[0]["market_scope"] == "US"


if __name__ == "__main__":
    _self_check()
    raise SystemExit(main())
