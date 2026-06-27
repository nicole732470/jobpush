#!/usr/bin/env python3
"""Fetch Workable boards exposed through public markdown feeds."""

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


def fetch_text(url: str) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "text/markdown,text/plain,text/html,*/*"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


def board_jobs_url(url: str) -> tuple[str, int]:
    split = urlsplit(url)
    host = split.netloc.casefold()
    parts = [part for part in split.path.split("/") if part]
    if host == "apply.workable.com":
        if not parts:
            raise ValueError(f"Cannot derive Workable slug from {url}")
        return f"https://apply.workable.com/{parts[0]}/jobs.md", 0
    if host == "jobs.workable.com" and len(parts) >= 2 and parts[0] == "company":
        company_md_url = f"https://jobs.workable.com/companies/{parts[1]}.md"
        markdown, _status = fetch_text(company_md_url)
        match = re.search(r"\[View jobs\]\(([^)]+/jobs\.md\?companyId=[^)]+)\)", markdown)
        if match:
            return match.group(1).replace("http://", "https://", 1), 1
        raise ValueError(f"Cannot find Workable company jobs.md link at {company_md_url}")
    if host == "jobs.workable.com" and parts and parts[0] == "companies" and url.endswith(".md"):
        markdown, _status = fetch_text(url)
        match = re.search(r"\[View jobs\]\(([^)]+/jobs\.md\?companyId=[^)]+)\)", markdown)
        if match:
            return match.group(1).replace("http://", "https://", 1), 1
        raise ValueError(f"Cannot derive Workable slug from {url}")
    if host == "jobs.workable.com" and parts and parts[0] == "jobs.md":
        return url.replace("http://", "https://", 1), 0
    raise ValueError(f"Workable adapter supports apply.workable.com and jobs.workable.com URLs, got {url}")


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
    match = re.search(r"/jobs/(?:view/)?([A-Za-z0-9-]+)\.md", job_url)
    if match:
        return match.group(1)
    return hashlib.sha1(f"{job_url}|{title}|{location}".encode("utf-8")).hexdigest()[:24]


def row_from_cells(cells: list[str], jobs_url: str, default_market: str) -> dict | None:
    if not cells:
        return None
    if cells[0].casefold() in {"title", "-------"} or set(cells[0]) <= {"-"}:
        return None
    if len(cells) == 7:
        title, department, location, employment_type, _salary, posted, details = cells
    elif len(cells) == 6:
        title, company, location, workplace, employment_type, details = cells
        department = workplace or company
        posted = ""
    else:
        return None
    if not title:
        return None
    job_url = parse_view_link(details, jobs_url)
    return {
        "external_job_id": external_id(job_url, title, location),
        "title": title,
        "normalized_title": normalize(title),
        "location": location,
        "category": "" if department == "—" else department,
        "job_url": job_url or jobs_url,
        "description_snippet": "",
        "market_scope": classify_market_scope(location, default_market),
        "posted_text": posted if posted != "—" else "",
        "employment_type": "" if employment_type == "—" else employment_type,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    args = ap.parse_args()

    started = time.monotonic()
    jobs_url, extra_requests = board_jobs_url(args.url)
    markdown, status = fetch_text(jobs_url)

    rows = []
    for line in markdown.splitlines():
        cells = split_markdown_row(line)
        row = row_from_cells(cells, jobs_url, args.default_market)
        if row:
            rows.append(row)

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    requests_count = 1 + extra_requests
    print(json.dumps({"status": "succeeded", "requests_count": requests_count, "pages_fetched": requests_count,
                      "raw_job_count": len(rows), "parsed_job_count": len(rows),
                      "duplicate_count": 0, "last_http_status": status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
