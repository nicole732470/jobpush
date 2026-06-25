#!/usr/bin/env python3
"""Fetch Paylocity Recruiting pages from public pageData / JSON-LD."""

from __future__ import annotations

import argparse
import csv
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
    return re.sub(r"\s+", " ", html.unescape(value or "")).strip()


def strip_html(value: str | None) -> str:
    return clean(re.sub(r"<[^>]+>", " ", html.unescape(value or "")))


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def fetch_text(url: str) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "text/html,*/*"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


def page_data(html_text: str) -> dict:
    match = re.search(r"window\.pageData\s*=\s*(\{.*?\});", html_text, re.S)
    if not match:
        return {}
    try:
        return json.loads(match.group(1))
    except json.JSONDecodeError:
        return {}


def json_ld_job(html_text: str) -> dict:
    for match in re.finditer(
        r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        html_text,
        re.S | re.I,
    ):
        try:
            payload = json.loads(clean(match.group(1)))
        except json.JSONDecodeError:
            continue
        candidates = payload if isinstance(payload, list) else [payload]
        for item in candidates:
            if isinstance(item, dict) and item.get("@type") == "JobPosting":
                return item
    return {}


def location_from_paylocity(job: dict) -> str:
    location = clean(job.get("LocationName"))
    address = job.get("JobLocation") or {}
    pieces = [address.get("City"), address.get("State"), address.get("Country")]
    structured = clean(", ".join(str(piece) for piece in pieces if piece))
    return structured or location


def location_from_json_ld(job: dict) -> str:
    locations = job.get("jobLocation") or []
    if isinstance(locations, dict):
        locations = [locations]
    names = []
    for location in locations:
        address = (location or {}).get("address") or {}
        pieces = [address.get("addressLocality"), address.get("addressRegion"), address.get("addressCountry")]
        value = clean(", ".join(str(piece) for piece in pieces if piece))
        if value:
            names.append(value)
    return "; ".join(names)


def row_from_paylocity_job(job: dict, base_url: str) -> dict:
    title = clean(job.get("JobTitle"))
    job_id = str(job.get("JobId") or "")
    location = location_from_paylocity(job)
    module = job.get("ModuleId")
    job_url = urljoin(base_url, f"/Recruiting/Jobs/Details/{job_id}") if job_id else base_url
    if module and job_id:
        job_url = urljoin(base_url, f"/Recruiting/Jobs/Details/{job_id}")
    return {
        "external_job_id": job_id or re.sub(r"\W+", "-", f"{title}-{location}")[:80],
        "title": title,
        "normalized_title": normalize(title),
        "location": location,
        "category": clean(job.get("HiringDepartment") or ""),
        "job_url": job_url,
        "description_snippet": strip_html(job.get("Description"))[:1000],
        "market_scope": classify_market_scope(location, "unknown"),
        "posted_text": clean(job.get("PublishedDate")),
        "employment_type": "Remote" if job.get("IsRemote") else "",
    }


def row_from_json_ld(job: dict, url: str) -> dict:
    title = clean(job.get("title"))
    location = location_from_json_ld(job)
    external_id = urlsplit(url).path.rstrip("/").split("/")[-2:]
    external_id_text = "-".join(external_id) if external_id else re.sub(r"\W+", "-", title)[:80]
    return {
        "external_job_id": external_id_text,
        "title": title,
        "normalized_title": normalize(title),
        "location": location,
        "category": "",
        "job_url": url,
        "description_snippet": strip_html(job.get("description"))[:1000],
        "market_scope": classify_market_scope(location, "unknown"),
        "posted_text": clean(job.get("datePosted")),
        "employment_type": clean(job.get("employmentType")),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    args = ap.parse_args()

    started = time.monotonic()
    html_text, status = fetch_text(args.url)
    data = page_data(html_text)
    rows = []

    for job in data.get("Jobs") or []:
        row = row_from_paylocity_job(job, args.url)
        if row["title"]:
            if row["market_scope"] == "unknown":
                row["market_scope"] = classify_market_scope(row["location"], args.default_market)
            rows.append(row)

    if not rows:
        job = json_ld_job(html_text)
        if job:
            row = row_from_json_ld(job, args.url)
            if row["market_scope"] == "unknown":
                row["market_scope"] = classify_market_scope(row["location"], args.default_market)
            if row["title"]:
                rows.append(row)

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
