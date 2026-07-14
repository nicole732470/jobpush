#!/usr/bin/env python3
"""Fetch Comeet hosted career boards via the public Careers API 2.0.

Accepts board URLs like:
  https://www.comeet.com/jobs/{company-slug}/{COMPANY.UID}
and extracts the public token embedded in the HTML page.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from urllib.request import Request, urlopen

from market_scope import classify_market_scope


FIELDS = [
    "external_job_id", "title", "normalized_title", "location", "category",
    "job_url", "description_snippet", "market_scope", "posted_text", "employment_type",
]

BOARD_RE = re.compile(
    r"comeet\.(?:com|co)/jobs/([^/?#]+)/([0-9A-Fa-f]+\.[0-9A-Fa-f]+)",
    re.I,
)
TOKEN_RE = re.compile(r'"token"\s*:\s*"([A-Z0-9]+)"', re.I)


def clean(value: object) -> str:
    return re.sub(r"\s+", " ", html.unescape("" if value is None else str(value))).strip()


def strip_html(value: object) -> str:
    return clean(re.sub(r"<[^>]+>", " ", html.unescape("" if value is None else str(value))))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def fetch_text(url: str) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "text/html,application/json"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


def fetch_json(url: str) -> tuple[object, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "application/json"})
    with urlopen(request, timeout=30) as response:
        return json.load(response), response.status


def board_parts(url: str) -> tuple[str, str]:
    match = BOARD_RE.search(url)
    if not match:
        raise ValueError(
            f"Comeet board URL must look like /jobs/{{slug}}/{{COMPANY.UID}}; got {url}"
        )
    return match.group(1), match.group(2)


def extract_token(page_html: str, page_url: str) -> str:
    query_token = parse_qs(urlsplit(page_url).query).get("token", [None])[0]
    if query_token:
        return query_token
    match = TOKEN_RE.search(page_html)
    if not match:
        raise ValueError("Could not find public Comeet careers token in board HTML")
    return match.group(1)


def rows_for(positions: list, default_market: str) -> list[dict]:
    rows = []
    for job in positions:
        location = clean((job.get("location") or {}).get("name"))
        market_scope = classify_market_scope(location, default_market)
        if market_scope != "US":
            continue
        title = clean(job.get("name") or job.get("title"))
        if not title:
            continue
        details = job.get("details") or []
        description = " ".join(
            strip_html(item.get("value")) for item in details if isinstance(item, dict)
        )
        job_url = clean(
            job.get("url_active_page")
            or job.get("url_comeet_hosted_page")
            or job.get("url_recruit_hosted_page")
            or ""
        )
        rows.append({
            "external_job_id": clean(job.get("uid") or job_url)[:200],
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": clean(job.get("department")),
            "job_url": job_url[:2000],
            "description_snippet": description[:1000],
            "market_scope": market_scope,
            "posted_text": clean(job.get("time_updated")),
            "employment_type": clean(job.get("employment_type")),
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    args = parser.parse_args()

    started = time.monotonic()
    _slug, company_uid = board_parts(args.url)
    page_html, page_status = fetch_text(args.url)
    token = extract_token(page_html, args.url)
    api = (
        f"https://www.comeet.co/careers-api/2.0/company/{company_uid}/positions"
        f"?token={token}&details=true"
    )
    payload, api_status = fetch_json(api)
    if isinstance(payload, dict):
        positions = payload.get("positions") or []
    elif isinstance(payload, list):
        positions = payload
    else:
        positions = []
    rows = rows_for(positions, args.default_market)

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({
        "status": "succeeded",
        "requests_count": 2,
        "pages_fetched": 2,
        "raw_job_count": len(positions),
        "parsed_job_count": len(rows),
        "duplicate_count": 0,
        "last_http_status": api_status or page_status,
        "latency_ms": round((time.monotonic() - started) * 1000),
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
