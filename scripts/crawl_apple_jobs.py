#!/usr/bin/env python3
"""Fetch Apple's public US search API into normalized adapter CSV."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen


FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: object) -> str:
    return re.sub(r"\s+", " ", "" if value is None else str(value)).strip()


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def fetch_page(endpoint: str, page: int, timeout: int) -> tuple[int, dict, int]:
    body = json.dumps({
        "query": "",
        "filters": {"locations": ["postLocation-USA"]},
        "page": page,
        "locale": "en-us",
        "sort": "",
        "format": {"longDate": "MMMM D, YYYY", "mediumDate": "MMM D, YYYY"},
    }).encode()
    request = Request(endpoint, data=body, method="POST", headers={
        "User-Agent": "JobPush/0.1", "Accept": "application/json",
        "Content-Type": "application/json",
    })
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            with urlopen(request, timeout=timeout) as response:
                return page, json.load(response)["res"], response.status
        except Exception as exc:  # retry transient Apple edge/API responses
            last_error = exc
            time.sleep(0.5 * (attempt + 1))
    raise RuntimeError(f"Apple page {page} failed after retries: {last_error}")


def row_from_job(job: dict, origin: str) -> dict[str, str]:
    external_id = clean(job.get("reqId") or job.get("id") or job.get("positionId"))
    position_id = clean(job.get("positionId") or external_id.removeprefix("PIPE-"))
    slug = clean(job.get("transformedPostingTitle"))
    team = job.get("team") or {}
    team_code = clean(team.get("teamCode"))
    path = f"/en-us/details/{position_id}/{slug}"
    if team_code:
        path = f"{path}?{urlencode({'team': team_code})}"
    locations = "; ".join(dict.fromkeys(clean(item.get("name")) for item in job.get("locations", []) if clean(item.get("name"))))
    weekly_hours = job.get("standardWeeklyHours")
    return {
        "external_job_id": external_id,
        "title": clean(job.get("postingTitle")),
        "normalized_title": normalize(clean(job.get("postingTitle"))),
        "location": locations,
        "category": clean(team.get("teamName")),
        "job_url": f"{origin}{path}",
        "description_snippet": clean(job.get("jobSummary"))[:1000],
        "market_scope": "US",
        "posted_text": clean(job.get("postingDate")),
        "employment_type": f"{weekly_hours} hours/week" if weekly_hours is not None else "",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US",), default="US")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--timeout", type=int, default=30)
    args = ap.parse_args()

    started = time.monotonic()
    parsed = urlsplit(args.url)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    endpoint = f"{origin}/api/v1/search"
    _, first, last_status = fetch_page(endpoint, 1, args.timeout)
    total = int(first.get("totalRecords") or 0)
    page_size = len(first.get("searchResults") or []) or 20
    total_pages = max(1, math.ceil(total / page_size))
    pages = {1: first}

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(fetch_page, endpoint, page, args.timeout)
                   for page in range(2, total_pages + 1)]
        for future in as_completed(futures):
            page, payload, last_status = future.result()
            pages[page] = payload

    rows: dict[str, dict[str, str]] = {}
    raw_count = 0
    for page in sorted(pages):
        jobs = pages[page].get("searchResults") or []
        raw_count += len(jobs)
        for job in jobs:
            row = row_from_job(job, origin)
            rows[row["external_job_id"]] = row

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows.values())

    print(json.dumps({"status": "succeeded", "requests_count": total_pages,
                      "pages_fetched": total_pages, "raw_job_count": raw_count,
                      "parsed_job_count": len(rows), "duplicate_count": raw_count - len(rows),
                      "last_http_status": last_status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
