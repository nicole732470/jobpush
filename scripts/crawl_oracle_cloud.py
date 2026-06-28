#!/usr/bin/env python3
"""Fetch a public Oracle Recruiting Cloud site into normalized adapter CSV."""

from __future__ import annotations

import argparse
import csv
import json
import re
import time
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


def get_json(base: str, params: dict[str, str]) -> tuple[dict, int]:
    url = f"{base}?{urlencode(params)}"
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "application/json"})
    with urlopen(request, timeout=60) as response:
        return json.load(response), response.status


def result_item(payload: dict) -> dict:
    items = payload.get("items") or []
    if not items:
        raise RuntimeError("Oracle response contained no search result item")
    return items[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="US")
    ap.add_argument("--page-size", type=int, default=200)
    args = ap.parse_args()

    started = time.monotonic()
    parsed = urlsplit(args.url)
    match = re.search(r"/sites/([^/]+)", parsed.path)
    if not parsed.hostname or not match:
        raise ValueError(f"Cannot derive Oracle site number from {args.url}")
    site_number = match.group(1)
    site_base_url = f"{parsed.scheme}://{parsed.netloc}{parsed.path[:match.end()]}"
    api = f"{parsed.scheme}://{parsed.netloc}/hcmRestApi/resources/latest/recruitingCEJobRequisitions"

    discovery, last_status = get_json(api, {
        "onlyData": "true",
        "finder": f"findReqs;siteNumber={site_number},limit=1,offset=0",
    })
    requests_count = 1
    locations = result_item(discovery).get("locationsFacet") or []
    us_location = next((item for item in locations if clean(item.get("Name")).casefold() == "united states"), None)
    if not us_location:
        raise RuntimeError("Oracle site did not expose a United States location facet")

    rows: dict[str, dict[str, str]] = {}
    offset = 0
    total = 1
    while offset < total:
        finder = (f"findReqs;siteNumber={site_number},limit={args.page_size},offset={offset},"
                  f"selectedLocationsFacet={us_location['Id']}")
        payload, last_status = get_json(api, {
            "onlyData": "true",
            "expand": "requisitionList.secondaryLocations",
            "finder": finder,
        })
        requests_count += 1
        item = result_item(payload)
        total = int(item.get("TotalJobsCount") or 0)
        postings = item.get("requisitionList") or []
        for job in postings:
            external_id = clean(job.get("Id"))
            rows[external_id] = {
                "external_job_id": external_id,
                "title": clean(job.get("Title")),
                "normalized_title": normalize(clean(job.get("Title"))),
                "location": clean(job.get("PrimaryLocation")),
                "category": clean(job.get("JobFamily") or job.get("JobFunction")),
                "job_url": f"{site_base_url}/job/{external_id}",
                "description_snippet": clean(job.get("ShortDescriptionStr"))[:1000],
                "market_scope": args.default_market,
                "posted_text": clean(job.get("PostedDate")),
                "employment_type": clean(job.get("WorkerType") or job.get("JobSchedule")),
            }
        if not postings:
            break
        offset += len(postings)

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows.values())

    print(json.dumps({"status": "succeeded", "requests_count": requests_count,
                      "pages_fetched": requests_count - 1, "raw_job_count": len(rows),
                      "parsed_job_count": len(rows), "duplicate_count": 0,
                      "last_http_status": last_status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
