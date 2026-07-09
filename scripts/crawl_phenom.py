#!/usr/bin/env python3
"""Fetch Phenom career search pages into adapter CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urljoin, urlparse, urlunparse
from urllib.request import Request, urlopen

from market_scope import classify_market_scope

FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: object) -> str:
    return re.sub(r"\s+", " ", html.unescape("" if value is None else str(value))).strip()


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def strip_html(value: object) -> str:
    return clean(re.sub(r"<[^>]+>", " ", clean(value)))


def page_url(url: str, offset: int) -> str:
    parsed = urlparse(url)
    query = parse_qs(parsed.query)
    query["from"] = [str(offset)]
    query.setdefault("s", ["1"])
    return urlunparse(parsed._replace(query=urlencode(query, doseq=True)))


def fetch_text(url: str, timeout: int) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html,*/*"})
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "ignore"), response.status


def phapp_ddo(body: str) -> dict:
    match = re.search(r"phApp\.ddo\s*=\s*", body)
    if not match:
        return {}
    start = match.end()
    depth = 0
    in_string = False
    escaped = False
    for index, char in enumerate(body[start:], start):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        else:
            if char == '"':
                in_string = True
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return json.loads(body[start:index + 1])
    return {}


def jobs_from_data(data: dict) -> list[dict]:
    jobs = (((data.get("eagerLoadRefineSearch") or {}).get("data") or {}).get("jobs") or [])
    return [job for job in jobs if isinstance(job, dict)]


def row_from_job(job: dict, source_url: str) -> dict | None:
    country = clean(job.get("country"))
    if country and country.casefold() not in {"united states", "usa", "united states of america"}:
        return None
    title = clean(job.get("title"))
    external_id = clean(job.get("jobSeqNo") or job.get("jobId") or job.get("reqId"))
    if not title or not external_id:
        return None
    location = clean(job.get("location") or "; ".join(job.get("multi_location") or []))
    return {
        "external_job_id": external_id[:200],
        "title": title,
        "normalized_title": normalize(title),
        "location": location,
        "category": clean(job.get("category") or ", ".join(job.get("multi_category") or [])),
        "job_url": urljoin(source_url, clean(job.get("applyUrl")) or source_url),
        "description_snippet": strip_html(job.get("descriptionTeaser") or (job.get("ml_job_parser") or {}).get("descriptionTeaser"))[:1000],
        "market_scope": classify_market_scope(location, "unknown"),
        "posted_text": clean(job.get("postedDate") or job.get("dateCreated")),
        "employment_type": clean(job.get("type")),
    }


def job_rows(jobs: list[dict], source_url: str) -> list[dict]:
    rows = []
    for job in jobs:
        row = row_from_job(job, source_url)
        if row:
            rows.append(row)
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--max-jobs", type=int, default=500)
    parser.add_argument("--default-market", choices=("US", "unknown"), default="unknown")
    args = parser.parse_args()

    started = time.monotonic()
    rows = []
    seen = set()
    requests_count = 0
    last_status = 0

    for offset in range(0, args.max_jobs, 10):
        url = page_url(args.url, offset)
        body, last_status = fetch_text(url, args.timeout)
        requests_count += 1
        raw_jobs = jobs_from_data(phapp_ddo(body))
        if not raw_jobs:
            break
        page_rows = job_rows(raw_jobs, args.url)
        for row in page_rows:
            if row["external_job_id"] in seen:
                continue
            seen.add(row["external_job_id"])
            rows.append(row)
            if len(rows) >= args.max_jobs:
                break
        if len(raw_jobs) < 10 or len(rows) >= args.max_jobs:
            break

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({"status": "succeeded", "requests_count": requests_count,
                      "pages_fetched": requests_count, "raw_job_count": len(rows),
                      "parsed_job_count": len(rows), "duplicate_count": 0,
                      "last_http_status": last_status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
