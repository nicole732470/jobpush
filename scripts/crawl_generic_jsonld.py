#!/usr/bin/env python3
"""Fetch JobPosting JSON-LD from a verified generic careers page."""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import urljoin
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


def fetch_text(url: str, timeout: int) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "text/html,*/*"})
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


def json_ld_payloads(body: str) -> list[object]:
    payloads: list[object] = []
    for match in re.finditer(
        r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        body,
        re.S | re.I,
    ):
        try:
            payloads.append(json.loads(html.unescape(match.group(1)).strip()))
        except json.JSONDecodeError:
            continue
    return payloads


def job_items(payload: object) -> list[dict]:
    if isinstance(payload, list):
        return [item for entry in payload for item in job_items(entry)]
    if not isinstance(payload, dict):
        return []
    nested = payload.get("@graph")
    if isinstance(nested, list):
        return [item for entry in nested for item in job_items(entry)]
    item_type = payload.get("@type")
    if item_type == "JobPosting" or (isinstance(item_type, list) and "JobPosting" in item_type):
        return [payload]
    return []


def location_text(job: dict) -> str:
    locations = job.get("jobLocation") or []
    if isinstance(locations, dict):
        locations = [locations]
    values = []
    for location in locations:
        address = (location or {}).get("address") or {}
        pieces = [
            address.get("addressLocality"),
            address.get("addressRegion"),
            address.get("addressCountry"),
        ]
        value = clean(", ".join(str(piece) for piece in pieces if piece))
        if value:
            values.append(value)
    return "; ".join(values)


def row_from_job(job: dict, source_url: str) -> dict | None:
    title = clean(job.get("title"))
    if not title:
        return None
    job_url = clean(job.get("url")) or source_url
    location = location_text(job)
    external_id = hashlib.sha1(f"{job_url}|{title}|{location}".encode("utf-8")).hexdigest()[:24]
    org = job.get("hiringOrganization") or {}
    return {
        "external_job_id": external_id,
        "title": title,
        "normalized_title": normalize(title),
        "location": location,
        "category": clean(job.get("occupationalCategory")),
        "job_url": urljoin(source_url, job_url),
        "description_snippet": strip_html(job.get("description"))[:1000],
        "market_scope": classify_market_scope(location, "unknown"),
        "posted_text": clean(job.get("datePosted")),
        "employment_type": clean(job.get("employmentType") or org.get("name")),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    started = time.monotonic()
    body, status = fetch_text(args.url, args.timeout)
    rows = []
    seen = set()
    for payload in json_ld_payloads(body):
        for job in job_items(payload):
            row = row_from_job(job, args.url)
            if not row or row["external_job_id"] in seen:
                continue
            seen.add(row["external_job_id"])
            rows.append(row)

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


if __name__ == "__main__":
    raise SystemExit(main())
