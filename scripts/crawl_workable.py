#!/usr/bin/env python3
"""Fetch Workable boards exposed through apply.workable.com/jobs.md."""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

from market_scope import classify_market_scope


FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: str | None) -> str:
    return re.sub(r"\s+", " ", html.unescape(value or "").replace("\\|", "|")).strip()


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def board_jobs_url(url: str) -> str:
    split = urlsplit(url)
    host = split.netloc.casefold()
    if host != "apply.workable.com":
        raise ValueError(f"Workable v1 only supports apply.workable.com URLs, got {url}")
    parts = [part for part in split.path.split("/") if part]
    if not parts:
        raise ValueError(f"Cannot derive Workable slug from {url}")
    return f"https://apply.workable.com/{parts[0]}/jobs.md"


def split_markdown_row(line: str) -> list[str]:
    line = line.strip()
    if not line.startswith("|") or not line.endswith("|"):
        return []
    return [clean(cell) for cell in line.strip("|").split("|")]


def parse_view_link(cell: str, base_url: str) -> str:
    match = re.search(r"\[[^\]]+\]\(([^)]+)\)", cell)
    if not match:
        return ""
    return urljoin(base_url, match.group(1))


def external_id(job_url: str, title: str, location: str) -> str:
    match = re.search(r"/jobs/view/([A-Za-z0-9]+)\.md", job_url)
    if match:
        return match.group(1)
    return hashlib.sha1(f"{job_url}|{title}|{location}".encode("utf-8")).hexdigest()[:24]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    args = ap.parse_args()

    started = time.monotonic()
    jobs_url = board_jobs_url(args.url)
    request = Request(jobs_url, headers={"User-Agent": "JobPush/0.1", "Accept": "text/markdown,text/plain,*/*"})
    with urlopen(request, timeout=30) as response:
        status = response.status
        markdown = response.read().decode("utf-8", errors="replace")

    rows = []
    for line in markdown.splitlines():
        cells = split_markdown_row(line)
        if len(cells) != 7:
            continue
        if cells[0].casefold() in {"title", "-------"} or set(cells[0]) <= {"-"}:
            continue
        title, department, location, employment_type, _salary, posted, details = cells
        if not title:
            continue
        job_url = parse_view_link(details, jobs_url)
        rows.append({
            "external_job_id": external_id(job_url, title, location),
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": department,
            "job_url": job_url or args.url,
            "description_snippet": "",
            "market_scope": classify_market_scope(location, args.default_market),
            "posted_text": posted if posted != "—" else "",
            "employment_type": "" if employment_type == "—" else employment_type,
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
