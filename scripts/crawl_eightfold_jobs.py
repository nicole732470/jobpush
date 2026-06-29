#!/usr/bin/env python3
"""Fetch an Eightfold career page's embedded positions into adapter CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import urlencode, urljoin
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
    request = Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html"})
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "ignore"), response.status


def pcsx_domain(body: str) -> str:
    match = re.search(r'<code[^>]*id="pcsx-data"[^>]*>(.*?)</code>', body, re.S)
    if not match:
        raise RuntimeError("Eightfold smartApplyData/pcsx-data not found")
    data = json.loads(html.unescape(match.group(1)))
    domain = clean(data.get("domain"))
    if not domain:
        raise RuntimeError("Eightfold pcsx-data domain not found")
    return domain


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "unknown"), default="US")
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    started = time.monotonic()
    if re.fullmatch(r"https?://[^/]+/?", args.url):
        args.url = args.url.rstrip("/") + "/careers"
    body, last_status = fetch_text(args.url, args.timeout)
    match = re.search(r'<code id="smartApplyData"[^>]*>(.*?)</code>', body, re.S)

    rows = []
    requests_count = 1
    if match:
        data = json.loads(html.unescape(match.group(1)))
        positions = data.get("positions") or []
    else:
        domain = pcsx_domain(body)
        positions = []
        start = 0
        total = 1
        while start < total:
            params = urlencode({"domain": domain, "query": "", "location": "", "start": str(start)})
            api_body, last_status = fetch_text(urljoin(args.url, f"/api/pcsx/search?{params}"), args.timeout)
            requests_count += 1
            payload = json.loads(api_body)
            data = payload.get("data") or {}
            current = data.get("positions") or []
            total = int(data.get("count") or 0)
            positions.extend(current)
            if not current:
                break
            start += len(current)

    for job in positions:
        title = clean(job.get("posting_name") or job.get("name"))
        external_id = clean(job.get("ats_job_id") or job.get("atsJobId") or job.get("displayJobId") or job.get("id"))
        if not title or not external_id:
            continue
        location = clean(job.get("location") or "; ".join(job.get("locations") or job.get("standardizedLocations") or []))
        path = clean(job.get("canonicalPositionUrl") or job.get("positionUrl") or f"/careers/job/{job.get('id')}")
        rows.append({
            "external_job_id": external_id,
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": clean(job.get("department") or job.get("business_unit")),
            "job_url": urljoin(args.url, path),
            "description_snippet": strip_html(job.get("job_description"))[:1000],
            "market_scope": classify_market_scope(location, "unknown"),
            "posted_text": clean(job.get("custom_data", {}).get("postedDate") if isinstance(job.get("custom_data"), dict) else job.get("postedTs") or job.get("creationTs")),
            "employment_type": clean(job.get("job_type") or job.get("type") or job.get("workLocationOption")),
        })

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
