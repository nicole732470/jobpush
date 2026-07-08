#!/usr/bin/env python3
"""Fetch public UKG UltiPro / recruiting.ultipro.com job boards."""

from __future__ import annotations

import argparse
import csv
import json
import re
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

from market_scope import classify_market_scope


USER_AGENT = "JobPush/0.1 (+public-career-site-monitor; contact=repository-owner)"
PAGE_SIZE = 50


@dataclass
class Job:
    external_job_id: str
    title: str
    normalized_title: str
    location: str
    category: str
    job_url: str
    description_snippet: str
    market_scope: str = "US"
    posted_text: str = ""
    employment_type: str = ""


def clean(value: str | None) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def normalize_title(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def parse_ultipro_url(url: str) -> tuple[str, str | None]:
    parts = urlsplit(url)
    if parts.netloc.casefold() != "recruiting.ultipro.com":
        raise ValueError(f"Not an UltiPro recruiting URL: {url}")
    segments = [segment for segment in parts.path.split("/") if segment]
    if len(segments) < 2 or segments[1].casefold() != "jobboard":
        raise ValueError(f"Cannot parse UltiPro tenant/board from {url}")
    tenant = segments[0]
    board_id = None
    if len(segments) >= 3 and re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        segments[2],
        flags=re.I,
    ):
        board_id = segments[2]
    return tenant, board_id


def fetch(url: str, *, method: str = "GET", payload: dict | None = None, timeout: int = 30) -> tuple[bytes, int, str]:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/json, text/html, */*",
    }
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json; charset=UTF-8"
        headers["X-Requested-With"] = "XMLHttpRequest"
        data = json.dumps(payload).encode("utf-8")
        method = "POST"
    request = Request(url, data=data, method=method, headers=headers)
    with urlopen(request, timeout=timeout) as response:
        body = response.read()
        final_url = response.geturl()
        return body, response.status, final_url


def resolve_board_id(tenant: str, board_id: str | None, seed_url: str, timeout: int) -> str:
    if board_id:
        return board_id
    list_jobs_url = f"https://recruiting.ultipro.com/{tenant}/JobBoard/ListJobs"
    _, _, final_url = fetch(list_jobs_url, timeout=timeout)
    _, resolved = parse_ultipro_url(final_url)
    if not resolved:
        raise ValueError(f"Could not resolve UltiPro board id from {final_url}")
    return resolved


def location_text(opportunity: dict) -> str:
    names: list[str] = []
    for item in opportunity.get("Locations") or []:
        address = (item or {}).get("Address") or {}
        state = ((address.get("State") or {}).get("Code")) or ""
        country = ((address.get("Country") or {}).get("Code")) or ""
        city = address.get("City") or ""
        localized = item.get("LocalizedDescription") or ""
        pieces = [piece for piece in (city, state, country) if piece]
        structured = clean(", ".join(pieces))
        names.append(structured or clean(localized))
    return "; ".join(dict.fromkeys(name for name in names if name))


def is_us_opportunity(opportunity: dict) -> bool:
    locations = opportunity.get("Locations") or []
    if not locations:
        return True
    for item in locations:
        country = (((item or {}).get("Address") or {}).get("Country") or {}).get("Code") or ""
        if country.upper() in {"USA", "US"}:
            return True
    return False


def employment_type(opportunity: dict) -> str:
    if opportunity.get("FullTime") is True:
        return "Full-time"
    if opportunity.get("FullTime") is False:
        return "Part-time"
    return ""


def opportunity_url(tenant: str, board_id: str, opportunity_id: str) -> str:
    return (
        f"https://recruiting.ultipro.com/{tenant}/JobBoard/{board_id}/"
        f"OpportunityDetail?opportunityId={opportunity_id}"
    )


def search_payload(skip: int) -> dict:
    return {
        "opportunitySearch": {
            "Top": PAGE_SIZE,
            "Skip": skip,
            "QueryString": "",
            "OrderBy": [{
                "Value": "postedDateDesc",
                "PropertyName": "PostedDate",
                "Ascending": False,
            }],
            "Filters": [],
        },
        "matchCriteria": {
            "PreferredJobs": [],
            "Educations": [],
            "LicenseAndCertifications": [],
            "Skills": [],
            "hasNoLicenses": False,
            "SkippedSkills": [],
        },
    }


def row_from_opportunity(tenant: str, board_id: str, opportunity: dict) -> Job:
    title = clean(opportunity.get("Title"))
    location = location_text(opportunity)
    opp_id = clean(opportunity.get("Id"))
    requisition = clean(opportunity.get("RequisitionNumber"))
    external_id = requisition or opp_id or re.sub(r"\W+", "-", f"{title}-{location}")[:80]
    return Job(
        external_job_id=external_id,
        title=title,
        normalized_title=normalize_title(title),
        location=location,
        category=clean(opportunity.get("JobCategoryName")),
        job_url=opportunity_url(tenant, board_id, opp_id) if opp_id else seed_board_url(tenant, board_id),
        description_snippet=clean(opportunity.get("BriefDescription"))[:1000],
        market_scope=classify_market_scope(location, "unknown"),
        posted_text=clean(opportunity.get("PostedDate")),
        employment_type=employment_type(opportunity),
    )


def seed_board_url(tenant: str, board_id: str) -> str:
    return f"https://recruiting.ultipro.com/{tenant}/JobBoard/{board_id}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--delay", type=float, default=0.25)
    parser.add_argument("--default-market", default="unknown")
    args = parser.parse_args()

    started = time.monotonic()
    requests_count = 0
    statuses: list[int] = []
    tenant, board_id = parse_ultipro_url(args.url)
    board_id = resolve_board_id(tenant, board_id, args.url, args.timeout)
    requests_count += 1
    statuses.append(200)

    api_url = (
        f"https://recruiting.ultipro.com/{tenant}/JobBoard/{board_id}/"
        "JobBoardView/LoadSearchResults"
    )
    all_jobs: dict[str, Job] = {}
    raw_job_count = 0
    skip = 0
    total_count = None

    while True:
        body, status, _ = fetch(api_url, payload=search_payload(skip), timeout=args.timeout)
        requests_count += 1
        statuses.append(status)
        payload = json.loads(body.decode("utf-8"))
        if total_count is None:
            total_count = int(payload.get("totalCount") or 0)
        opportunities = payload.get("opportunities") or []
        raw_job_count += len(opportunities)
        for opportunity in opportunities:
            if not is_us_opportunity(opportunity):
                continue
            job = row_from_opportunity(tenant, board_id, opportunity)
            if job.market_scope == "unknown" and args.default_market != "unknown":
                job.market_scope = classify_market_scope(job.location, args.default_market)
            all_jobs[job.external_job_id] = job
        skip += len(opportunities)
        if not opportunities or skip >= (total_count or 0):
            break
        time.sleep(args.delay)

    fieldnames = list(Job.__dataclass_fields__)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for job in all_jobs.values():
            writer.writerow(asdict(job))

    print(json.dumps({
        "status": "succeeded",
        "requests_count": requests_count,
        "pages_fetched": max(1, (skip + PAGE_SIZE - 1) // PAGE_SIZE),
        "raw_job_count": raw_job_count,
        "parsed_job_count": len(all_jobs),
        "duplicate_count": max(0, raw_job_count - len(all_jobs)),
        "last_http_status": statuses[-1],
        "latency_ms": round((time.monotonic() - started) * 1000),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
