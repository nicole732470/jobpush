#!/usr/bin/env python3
"""Fetch public Rippling ATS job boards.

Rippling boards are static Next.js pages. The list page exposes job-detail
links, and each detail page carries structured job data in __NEXT_DATA__.
This adapter intentionally avoids browser automation.
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
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

from market_scope import STATE_CODES, US_STATES, classify_market_scope


FIELDS = [
    "external_job_id",
    "title",
    "normalized_title",
    "location",
    "category",
    "job_url",
    "description_snippet",
    "market_scope",
    "posted_text",
    "employment_type",
]


def clean(value: str | None) -> str:
    return re.sub(r"\s+", " ", html.unescape(value or "")).strip()


def strip_html(value: str | None) -> str:
    return clean(re.sub(r"<[^>]+>", " ", html.unescape(value or "")))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def fetch_text(url: str) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "text/html,*/*"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


def board_url(url: str) -> str:
    split = urlsplit(url)
    if split.netloc.casefold() != "ats.rippling.com":
        raise ValueError(f"Rippling adapter only supports ats.rippling.com URLs, got {url}")
    parts = [part for part in split.path.split("/") if part]
    if len(parts) >= 2 and parts[1] == "jobs":
        return f"https://ats.rippling.com/{parts[0]}/jobs"
    if parts:
        return f"https://ats.rippling.com/{parts[0]}/jobs"
    raise ValueError(f"Cannot derive Rippling board slug from {url}")


def job_links(list_html: str, base_url: str) -> list[str]:
    split = urlsplit(base_url)
    prefix = "/" + "/".join([part for part in split.path.split("/") if part][:2]) + "/"
    links = set()
    for href in re.findall(r'href=["\']([^"\']+/jobs/[^"\']+)["\']', list_html):
        href = html.unescape(href)
        if href.startswith(prefix) and not href.rstrip("/").endswith("/jobs"):
            links.add(urljoin(base_url, href))
    return sorted(links)


def next_data(page_html: str) -> dict:
    match = re.search(r'<script id=["\']__NEXT_DATA__["\'] type=["\']application/json["\']>(.*?)</script>', page_html, re.S)
    if not match:
        return {}
    try:
        return json.loads(html.unescape(match.group(1)))
    except json.JSONDecodeError:
        return {}


def location_text(job: dict) -> str:
    locations = job.get("workLocations") or []
    if isinstance(locations, dict):
        locations = [locations]
    names = []
    for location in locations:
        if not isinstance(location, dict):
            continue
        label = location.get("displayName") or location.get("name")
        address = location.get("address") or {}
        pieces = [
            label,
            address.get("city"),
            address.get("state") or address.get("region"),
            address.get("country"),
        ]
        value = clean(", ".join(str(piece) for piece in pieces if piece))
        if value and value not in names:
            names.append(value)
    return "; ".join(names)


def location_from_description(job: dict) -> str:
    description = job.get("description") or {}
    if not isinstance(description, dict):
        return ""
    company_html = html.unescape(description.get("company") or "")
    states = "|".join(re.escape(state.title()) for state in US_STATES)
    codes = "|".join(sorted(STATE_CODES))
    match = re.search(
        rf">\s*([^<>|]+,\s*(?:{states}|{codes}))\s*(?:&nbsp;|\s)*\|",
        company_html,
    )
    if match:
        return clean(match.group(1))
    company_text = strip_html(company_html)
    match = re.search(rf"\b([A-Z][A-Za-z .'-]+,\s*(?:{states}|{codes}))\s*\|", company_text)
    return clean(match.group(1)) if match else ""


def department_text(job: dict) -> str:
    department = job.get("department") or {}
    if isinstance(department, dict):
        return clean(department.get("name") or department.get("base_department") or "")
    return clean(str(department))


def employment_text(job: dict) -> str:
    employment = job.get("employmentType") or {}
    if isinstance(employment, dict):
        return clean(employment.get("id") or employment.get("label") or "")
    return clean(str(employment))


def description_text(job: dict) -> str:
    description = job.get("description") or {}
    if isinstance(description, dict):
        pieces = [description.get("role"), description.get("company")]
        return strip_html(" ".join(piece for piece in pieces if piece))[:1000]
    return strip_html(str(description))[:1000]


def row_from_detail(url: str, page_html: str, default_market: str) -> dict | None:
    data = next_data(page_html)
    job = (((data.get("props") or {}).get("pageProps") or {}).get("apiData") or {}).get("jobPost") or {}
    title = clean(job.get("name"))
    if not title:
        return None
    location = location_text(job) or location_from_description(job)
    external_id = clean(job.get("uuid")) or hashlib.sha1(url.encode("utf-8")).hexdigest()[:24]
    job_url = clean(job.get("url")) or url
    market_scope = classify_market_scope(location, default_market)
    return {
        "external_job_id": external_id,
        "title": title,
        "normalized_title": normalize(title),
        "location": location,
        "category": department_text(job),
        "job_url": job_url,
        "description_snippet": description_text(job),
        "market_scope": market_scope,
        "posted_text": clean(job.get("createdOn")),
        "employment_type": employment_text(job),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    args = ap.parse_args()

    started = time.monotonic()
    base_url = board_url(args.url)
    list_html, status = fetch_text(base_url)
    links = job_links(list_html, base_url)

    rows = []
    pages_fetched = 1
    last_status = status
    for link in links:
        detail_html, last_status = fetch_text(link)
        pages_fetched += 1
        row = row_from_detail(link, detail_html, args.default_market)
        if row:
            rows.append(row)

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({
        "status": "succeeded",
        "requests_count": pages_fetched,
        "pages_fetched": pages_fetched,
        "raw_job_count": len(rows),
        "parsed_job_count": len(rows),
        "duplicate_count": 0,
        "last_http_status": last_status,
        "latency_ms": round((time.monotonic() - started) * 1000),
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
