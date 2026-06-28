#!/usr/bin/env python3
"""Fetch a public SmartRecruiters company board into JobPush CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

from market_scope import classify_market_scope

FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: object | None) -> str:
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        value = json.dumps(value, ensure_ascii=False)
    return re.sub(r"\s+", " ", html.unescape(str(value))).strip()


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def company_token(url: str) -> str:
    split = urlsplit(url)
    parts = [part for part in split.path.split("/") if part]
    if split.netloc.casefold() == "api.smartrecruiters.com" and len(parts) >= 3 and parts[:2] == ["v1", "companies"]:
        return parts[2]
    if not parts:
        raise ValueError(f"Cannot derive SmartRecruiters company token from {url}")
    return parts[0]


def get_json(url: str) -> tuple[dict, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "application/json"})
    with urlopen(request, timeout=30) as response:
        return json.load(response), response.status


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    ap.add_argument("--page-size", type=int, default=100)
    ap.add_argument("--max-pages", type=int, default=20)
    args = ap.parse_args()

    started = time.monotonic()
    token = company_token(args.url)
    rows: dict[str, dict[str, str]] = {}
    offset = 0
    requests_count = 0
    last_status = 0
    total = 1
    pages = 0
    while offset < total and pages < args.max_pages:
        query = urlencode({"limit": args.page_size, "offset": offset})
        payload, last_status = get_json(f"https://api.smartrecruiters.com/v1/companies/{token}/postings?{query}")
        requests_count += 1
        pages += 1
        content = payload.get("content") or []
        total = int(payload.get("totalFound") or payload.get("total") or len(content))
        for job in content:
            location_obj = job.get("location") or {}
            location = clean(location_obj.get("fullLocation") or location_obj.get("city") or location_obj.get("region"))
            external_id = clean(job.get("id") or job.get("refNumber"))
            title = clean(job.get("name") or job.get("title"))
            department = job.get("department")
            if isinstance(department, dict):
                category = clean(department.get("label") or department.get("name") or department.get("id"))
            else:
                category = clean(department or job.get("industry"))
            rows[external_id] = {
                "external_job_id": external_id,
                "title": title,
                "normalized_title": normalize(title),
                "location": location,
                "category": category,
                "job_url": clean(job.get("ref") or f"https://jobs.smartrecruiters.com/{token}/{external_id}"),
                "description_snippet": clean(job.get("description"))[:1000],
                "market_scope": classify_market_scope(location, args.default_market),
                "posted_text": clean(job.get("releasedDate") or job.get("updatedDate")),
                "employment_type": clean(job.get("typeOfEmployment") or job.get("experienceLevel")),
            }
        if not content:
            break
        offset += len(content)

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows.values())

    print(json.dumps({"status": "succeeded", "requests_count": requests_count,
                      "pages_fetched": pages, "raw_job_count": total,
                      "parsed_job_count": len(rows), "duplicate_count": max(total - len(rows), 0),
                      "last_http_status": last_status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
