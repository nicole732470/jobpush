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
from urllib.request import Request, urlopen

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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "unknown"), default="US")
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    started = time.monotonic()
    request = Request(args.url, headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html"})
    with urlopen(request, timeout=args.timeout) as response:
        body = response.read().decode("utf-8", "ignore")
        last_status = response.status
    match = re.search(r'<code id="smartApplyData"[^>]*>(.*?)</code>', body, re.S)
    if not match:
        raise RuntimeError("Eightfold smartApplyData not found")
    data = json.loads(html.unescape(match.group(1)))

    rows = []
    for job in data.get("positions") or []:
        title = clean(job.get("posting_name") or job.get("name"))
        external_id = clean(job.get("ats_job_id") or job.get("id"))
        if not title or not external_id:
            continue
        rows.append({
            "external_job_id": external_id,
            "title": title,
            "normalized_title": normalize(title),
            "location": clean(job.get("location") or "; ".join(job.get("locations") or [])),
            "category": clean(job.get("department") or job.get("business_unit")),
            "job_url": clean(job.get("canonicalPositionUrl") or f"{args.url.rstrip('/')}/job/{job.get('id')}"),
            "description_snippet": strip_html(job.get("job_description"))[:1000],
            "market_scope": args.default_market,
            "posted_text": clean(job.get("custom_data", {}).get("postedDate") if isinstance(job.get("custom_data"), dict) else ""),
            "employment_type": clean(job.get("job_type") or job.get("type")),
        })

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({"status": "succeeded", "requests_count": 1,
                      "pages_fetched": 1, "raw_job_count": len(rows),
                      "parsed_job_count": len(rows), "duplicate_count": 0,
                      "last_http_status": last_status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
