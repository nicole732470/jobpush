#!/usr/bin/env python3
"""Fetch ApplicantPro public job boards via their stable JSON endpoint."""

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
    return re.sub(r"\s+", " ", html.unescape(str(value or ""))).strip()


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def fetch_text(url: str, accept: str = "text/html") -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": accept})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


def board_config(board_html: str, page_url: str) -> tuple[str, str, int, dict]:
    host = urlsplit(page_url).netloc.lower()
    subdomain = host.split(".applicantpro.com", 1)[0]
    domain = "applicantpro.com"
    domain_match = re.search(r'domainName\s*:\s*"([^"]+)"', board_html)
    subdomain_match = re.search(r'subdomainName\s*:\s*"([^"]+)"', board_html)
    domain_id_match = re.search(r"domainId\s*:\s*(\d+)", board_html)
    params_match = re.search(r"getParams\s*:\s*(\{.*?\})\s*,\s*domainName", board_html, re.S)
    if domain_match:
        domain = domain_match.group(1)
    if subdomain_match:
        subdomain = subdomain_match.group(1)
    if not domain_id_match or not params_match:
        raise ValueError("ApplicantPro board config not found")
    return subdomain, domain, int(domain_id_match.group(1)), json.loads(params_match.group(1))


def parse_rows(payload: dict, default_market: str) -> list[dict]:
    rows: list[dict] = []
    for job in payload.get("data", {}).get("jobs", []) or []:
        title = clean(job.get("title"))
        job_url = clean(job.get("jobUrl"))
        if not title or not job_url:
            continue
        location = clean(job.get("jobLocation") or ", ".join(
            part for part in [job.get("city"), job.get("abbreviation") or job.get("stateName"), job.get("iso3")]
            if part
        ))
        market_scope = classify_market_scope(location, default_market)
        if market_scope != "US":
            continue
        rows.append({
            "external_job_id": clean(job.get("id")) or normalize(job_url)[:64],
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": clean(job.get("classification") or job.get("orgTitle") or job.get("jobCategory")),
            "job_url": job_url,
            "description_snippet": clean(" · ".join(part for part in [
                job.get("classification"), job.get("employmentType"), job.get("workplaceType"), location
            ] if part)),
            "market_scope": market_scope,
            "posted_text": clean(job.get("startDateRef")),
            "employment_type": clean(job.get("employmentType")),
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "unknown"), default="unknown")
    args = parser.parse_args()

    started = time.monotonic()
    board_html, status = fetch_text(args.url)
    subdomain, domain, domain_id, get_params = board_config(board_html, args.url)
    api_url = f"https://{subdomain}.{domain}/core/jobs/{domain_id}?{urlencode({'getParams': json.dumps(get_params)})}"
    payload_text, api_status = fetch_text(api_url, "application/json")
    rows = parse_rows(json.loads(payload_text), args.default_market)

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({"status": "succeeded", "requests_count": 2,
                      "pages_fetched": 1, "raw_job_count": len(rows),
                      "parsed_job_count": len(rows), "duplicate_count": 0,
                      "last_http_status": api_status or status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


def _self_check() -> None:
    html_sample = 'domainId : 863, getParams : {"countryAbbreviation":"","isInternal":0}, domainName : "applicantpro.com", subdomainName : "asirobots"'
    assert board_config(html_sample, "https://asirobots.applicantpro.com/jobs")[:3] == ("asirobots", "applicantpro.com", 863)
    rows = parse_rows({"data": {"jobs": [{
        "id": 1, "title": "Product Manager", "jobUrl": "https://x/jobs/1",
        "jobLocation": "Chicago, Illinois, USA", "classification": "Product",
        "employmentType": "Full Time",
    }]}}, "unknown")
    assert rows[0]["market_scope"] == "US"


if __name__ == "__main__":
    _self_check()
    raise SystemExit(main())
