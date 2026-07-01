#!/usr/bin/env python3
"""Fetch Uber Careers search JSON into JobPush's normalized adapter CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urljoin, urlsplit, urlunsplit
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from market_scope import classify_market_scope

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


def fetch(url: str, referer: str, timeout: int) -> tuple[dict, int]:
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": referer,
    }
    for _ in range(5):
        request = Request(url, headers=headers)
        try:
            with urlopen(request, timeout=timeout) as response:
                return json.load(response), response.status
        except HTTPError as exc:
            if exc.code in {301, 302, 303, 307, 308} and exc.headers.get("Location"):
                url = urljoin(url, exc.headers["Location"])
                continue
            raise
    raise RuntimeError(f"Too many redirects for Uber jobs search API: {url}")


def search_params(raw_url: str) -> dict[str, str]:
    split = urlsplit(raw_url)
    params = dict(parse_qsl(split.query, keep_blank_values=True))
    if "locale" not in params:
        path_parts = [part for part in split.path.split("/") if part]
        if path_parts and len(path_parts[0]) == 2:
            params.setdefault("locale", path_parts[0])
    params.setdefault("pagesize", "50")
    return params


def search_url(origin: str, params: dict[str, str], page: int) -> str:
    query = dict(params)
    query["page"] = str(page)
    return urljoin(origin, f"/api/jobs/search?{urlencode(query)}")


def format_location(locations: list[dict]) -> str:
    parts = []
    for loc in locations:
        address = clean(loc.get("Address"))
        if address:
            parts.append(address)
            continue
        city = clean(loc.get("City"))
        region = clean(loc.get("Region"))
        country = clean(loc.get("Country"))
        chunk = ", ".join(part for part in (city, region, country) if part)
        if chunk:
            parts.append(chunk)
    deduped = []
    for part in parts:
        if part not in deduped:
            deduped.append(part)
    return "; ".join(deduped)


def market_scope_for_job(locations: list[dict], fallback: str) -> str:
    if not locations:
        return fallback
    scopes = {classify_market_scope(format_location([loc]), fallback="unknown") for loc in locations}
    if "US" in scopes:
        return "US"
    if scopes == {"unknown"}:
        return fallback
    if "non-US" in scopes:
        return "non-US"
    return fallback


def job_url(origin: str, job: dict) -> str:
    urls = job.get("Urls") or []
    for entry in urls:
        path = clean((entry or {}).get("Url"))
        if path:
            return urljoin(origin, path)
    return urljoin(origin, f"/en/jobs/{clean(job.get('Id'))}/")


def row_from_job(job: dict, origin: str, fallback: str) -> dict[str, str]:
    locations = job.get("Locations") or []
    location = format_location(locations)
    teams = [clean(team) for team in (job.get("Teams") or []) if clean(team)]
    return {
        "external_job_id": clean(job.get("Id") or job.get("Reference")),
        "title": clean(job.get("Title")),
        "normalized_title": normalize(clean(job.get("Title"))),
        "location": location,
        "category": ", ".join(teams),
        "job_url": job_url(origin, job),
        "description_snippet": strip_html(job.get("Description"))[:1000],
        "market_scope": market_scope_for_job(locations, fallback),
        "posted_text": clean(job.get("DisplayDate")),
        "employment_type": clean(job.get("ContractType")),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "unknown"), default="unknown")
    parser.add_argument("--page-size", type=int, default=50)
    parser.add_argument("--max-pages", type=int, default=200)
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    started = time.monotonic()
    split = urlsplit(args.url)
    origin = f"{split.scheme}://{split.netloc}"
    referer = urlunsplit((split.scheme, split.netloc, split.path, split.query, ""))
    params = search_params(args.url)
    params["pagesize"] = str(args.page_size)

    rows: dict[str, dict[str, str]] = {}
    requests_count = 0
    last_status = 0
    total_pages = 1
    for page in range(1, args.max_pages + 1):
        payload, last_status = fetch(search_url(origin, params, page), referer, args.timeout)
        requests_count += 1
        total_pages = max(1, int(payload.get("totalPages") or 1))
        for job in payload.get("jobs") or []:
            row = row_from_job(job, origin, args.default_market)
            if row["external_job_id"]:
                rows[row["external_job_id"]] = row
        if page >= total_pages:
            break

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows.values())

    print(json.dumps({
        "status": "succeeded",
        "requests_count": requests_count,
        "pages_fetched": min(total_pages, args.max_pages),
        "raw_job_count": len(rows),
        "parsed_job_count": len(rows),
        "duplicate_count": 0,
        "last_http_status": last_status,
        "latency_ms": round((time.monotonic() - started) * 1000),
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
