#!/usr/bin/env python3
"""Thin Brassring crawler for tenant boards that include partnerid+siteid.

Generic Home shells without partnerid are rejected upstream and are not crawlable.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import parse_qs, urljoin, urlsplit
from urllib.request import Request, urlopen

from market_scope import classify_market_scope


FIELDS = [
    "external_job_id", "title", "normalized_title", "location", "category",
    "job_url", "description_snippet", "market_scope", "posted_text", "employment_type",
]


def clean(value: object) -> str:
    return re.sub(r"\s+", " ", html.unescape("" if value is None else str(value))).strip()


def strip_html(value: str) -> str:
    return clean(re.sub(r"<[^>]+>", " ", value))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def require_tenant(url: str) -> None:
    query = parse_qs(urlsplit(url).query)
    if not query.get("partnerid") or not query.get("siteid"):
        raise ValueError(
            "Brassring board URL must include partnerid and siteid query params; "
            f"got {url}"
        )


def fetch_text(url: str) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "text/html"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


CARD_RE = re.compile(
    r'<a[^>]+href=["\']([^"\']*(?:JobDetails|jobdetails|cim_jobdetail)[^"\']*)["\'][^>]*>(.*?)</a>',
    re.I | re.S,
)
TITLE_RE = re.compile(r"<[^>]+>", re.S)


def rows_for(body: str, source_url: str, default_market: str) -> list[dict]:
    rows = []
    seen = set()
    for href, inner in CARD_RE.findall(body):
        title = strip_html(inner)
        if len(title) < 3:
            continue
        job_url = urljoin(source_url, clean(href))
        external_id = hashlib.sha1(urlsplit(job_url).path.encode("utf-8")).hexdigest()[:24]
        if external_id in seen:
            continue
        seen.add(external_id)
        location = ""
        market_scope = classify_market_scope(location, default_market)
        if default_market == "US" and market_scope == "unknown":
            market_scope = "US"
        if market_scope != "US":
            continue
        rows.append({
            "external_job_id": external_id,
            "title": title[:500],
            "normalized_title": normalize(title),
            "location": location,
            "category": "",
            "job_url": job_url[:2000],
            "description_snippet": title[:1000],
            "market_scope": market_scope,
            "posted_text": "",
            "employment_type": "",
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="US")
    args = parser.parse_args()

    started = time.monotonic()
    require_tenant(args.url)
    body, status = fetch_text(args.url)
    rows = rows_for(body, args.url, args.default_market)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({
        "status": "succeeded",
        "requests_count": 1,
        "pages_fetched": 1,
        "raw_job_count": len(rows),
        "parsed_job_count": len(rows),
        "duplicate_count": 0,
        "last_http_status": status,
        "latency_ms": round((time.monotonic() - started) * 1000),
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
