#!/usr/bin/env python3
"""Fetch a public Workday CXS site into JobPush's normalized adapter CSV."""

from __future__ import annotations

import argparse
import csv
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
    return re.sub(r"\s+", " ", value or "").strip()


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def post_json(url: str, payload: dict) -> tuple[dict, int]:
    request = Request(url, data=json.dumps(payload).encode(), method="POST",
                      headers={"User-Agent": "JobPush/0.1", "Accept": "application/json",
                               "Content-Type": "application/json"})
    with urlopen(request, timeout=30) as response:
        return json.load(response), response.status


def workday_site_from_path(path: str) -> str | None:
    """Return the Workday recruiting site slug from a board or job-detail URL.

    Tavily often returns URLs like
    /en-US/aig/job/Some-Role/JR123. The CXS API site is "aig", not "en-US".
    Board URLs may also be just /Chegg. Keep this tolerant because Workday
    tenants vary heavily.
    """
    parts = [part for part in path.split("/") if part]
    if not parts:
        return None
    if re.fullmatch(r"[a-z]{2}(?:-[A-Z]{2})?", parts[0]):
        parts = parts[1:]
    if not parts:
        return None
    return parts[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    ap.add_argument("--page-size", type=int, default=20)
    args = ap.parse_args()

    started = time.monotonic()
    parsed = urlsplit(args.url)
    site = workday_site_from_path(parsed.path)
    tenant = parsed.hostname.split(".")[0] if parsed.hostname else None
    if not tenant or not site:
        raise ValueError(f"Cannot derive Workday tenant/site from {args.url}")
    endpoint = f"{parsed.scheme}://{parsed.netloc}/wday/cxs/{tenant}/{site}/jobs"

    rows: dict[str, dict[str, str]] = {}
    offset = 0
    requests_count = 0
    last_status = 0
    total = 1
    while offset < total:
        payload, last_status = post_json(endpoint, {
            "appliedFacets": {}, "limit": args.page_size, "offset": offset, "searchText": ""
        })
        requests_count += 1
        total = int(payload.get("total", 0))
        postings = payload.get("jobPostings", [])
        for job in postings:
            bullets = job.get("bulletFields") or []
            external_id = clean(bullets[0] if bullets else job.get("externalPath"))
            title = clean(job.get("title"))
            if not external_id or not title:
                continue
            path = clean(job.get("externalPath"))
            rows[external_id] = {
                "external_job_id": external_id,
                "title": title,
                "normalized_title": normalize(title),
                "location": clean(job.get("locationsText")),
                "category": "",
                "job_url": f"{parsed.scheme}://{parsed.netloc}/{site}{path}",
                "description_snippet": "",
                "market_scope": classify_market_scope(
                    clean(job.get("locationsText")), args.default_market
                ),
                "posted_text": clean(job.get("postedOn")),
                "employment_type": clean(job.get("timeType")),
            }
        if not postings:
            break
        offset += len(postings)

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows.values())

    print(json.dumps({"status": "succeeded", "requests_count": requests_count,
                      "pages_fetched": requests_count, "raw_job_count": total,
                      "parsed_job_count": len(rows), "duplicate_count": total - len(rows),
                      "last_http_status": last_status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
