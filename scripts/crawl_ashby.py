#!/usr/bin/env python3
"""Fetch a public Ashby job board into JobPush's normalized adapter CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from market_scope import classify_market_scope

FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: str | None) -> str:
    return re.sub(r"\s+", " ", html.unescape(value or "")).strip()


def strip_html(value: str | None) -> str:
    return clean(re.sub(r"<[^>]+>", " ", html.unescape(value or "")))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def board_token(url: str) -> str:
    parts = [part for part in urlsplit(url).path.split("/") if part]
    if not parts:
        raise ValueError(f"Cannot derive Ashby board token from {url}")
    return parts[0]


def location_text(job: dict) -> str:
    location = job.get("location")
    if isinstance(location, dict):
        return clean(location.get("name") or location.get("location") or location.get("address"))
    if isinstance(location, str):
        return clean(location)
    locations = job.get("locations")
    if isinstance(locations, list):
        parts = []
        for item in locations:
            if isinstance(item, dict):
                parts.append(clean(item.get("name") or item.get("location") or item.get("address")))
            else:
                parts.append(clean(str(item)))
        return clean(", ".join(part for part in parts if part))
    return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    args = ap.parse_args()

    started = time.monotonic()
    token = board_token(args.url)
    endpoint = f"https://api.ashbyhq.com/posting-api/job-board/{token}?includeCompensation=true"
    request = Request(endpoint, headers={"User-Agent": "JobPush/0.1", "Accept": "application/json"})
    with urlopen(request, timeout=30) as response:
        status = response.status
        payload = json.load(response)

    jobs = payload.get("jobs") if isinstance(payload, dict) else []
    rows = []
    for job in jobs or []:
        location = location_text(job)
        department = job.get("department")
        if isinstance(department, dict):
            category = clean(department.get("name"))
        else:
            category = clean(str(department or ""))
        external_id = clean(job.get("id") or job.get("jobId"))
        title = clean(job.get("title"))
        rows.append({
            "external_job_id": external_id,
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": category,
            "job_url": clean(job.get("jobUrl") or job.get("hostedUrl") or f"https://jobs.ashbyhq.com/{token}/{external_id}"),
            "description_snippet": strip_html(job.get("descriptionHtml") or job.get("descriptionPlain"))[:1000],
            "market_scope": classify_market_scope(location, args.default_market),
            "posted_text": clean(job.get("publishedAt") or job.get("updatedAt")),
            "employment_type": clean(job.get("employmentType") or job.get("workplaceType")),
        })

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({"status": "succeeded", "requests_count": 1, "pages_fetched": 1,
                      "raw_job_count": len(rows), "parsed_job_count": len(rows),
                      "duplicate_count": 0, "last_http_status": status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
