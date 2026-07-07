#!/usr/bin/env python3
"""Fetch Dover career pages through their public careers-page API."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from market_scope import NON_US_MARKERS, classify_market_scope


FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]
API_BASE = "https://app.dover.com/api/v1"


def clean(value: object) -> str:
    return re.sub(r"\s+", " ", html.unescape("" if value is None else str(value))).strip()


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def title_out_of_scope(title: str) -> bool:
    lowered = title.casefold()
    return any(re.search(rf"\b{re.escape(marker)}\b", lowered) for marker in NON_US_MARKERS)


def fetch_json(url: str) -> tuple[object, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": "application/json"})
    with urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8")), response.status


UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)


def client_hint(source_url: str) -> tuple[str | None, str | None]:
    parts = [part for part in urlsplit(source_url).path.split("/") if part]
    if len(parts) >= 2 and parts[0] == "jobs":
        return None, parts[1]
    if "careers" in parts:
        idx = parts.index("careers")
        client_id = parts[idx + 1] if idx + 1 < len(parts) and UUID_RE.match(parts[idx + 1]) else None
        slug = parts[0] if parts and parts[0].casefold() not in {"dover", "jobs"} else None
        return client_id, slug
    return None, None


def client_for(source_url: str) -> tuple[dict, int]:
    client_id, slug = client_hint(source_url)
    if slug:
        data, status = fetch_json(f"{API_BASE}/careers-page-slug/{slug}")
        return data, status
    if client_id:
        data, status = fetch_json(f"{API_BASE}/careers-page/{client_id}")
        return data, status
    raise ValueError(f"Cannot derive Dover client from {source_url}")


def us_locations(job: dict) -> tuple[str, str]:
    us_values: list[str] = []
    all_values: list[str] = []
    for loc in job.get("locations") or []:
        option = loc.get("location_option") or {}
        name = clean(loc.get("name") or option.get("display_name"))
        if re.search(r"\b(international|global)\b", name, re.I):
            continue
        if name:
            all_values.append(name)
        country = clean(option.get("country")).upper()
        if country == "US" and name:
            us_values.append(name)
        elif name and classify_market_scope(name, "unknown") == "US":
            us_values.append(name)
    values = us_values or all_values
    location = "; ".join(dict.fromkeys(values))
    return location, "US" if us_values else classify_market_scope(location, "unknown")


def rows_for(source_url: str) -> tuple[list[dict], int, int]:
    client, status = client_for(source_url)
    client_id = clean(client.get("id"))
    slug = clean(client.get("slug"))
    rows: list[dict] = []
    requests = 1
    offset = 0
    while True:
        page, _page_status = fetch_json(f"{API_BASE}/careers-page/{client_id}/jobs?limit=100&offset={offset}")
        requests += 1
        for job in page.get("results") or []:
            title = clean(job.get("title"))
            if not title or re.search(r"\bgeneral application\b", title, re.I) or title_out_of_scope(title):
                continue
            location, market_scope = us_locations(job)
            if market_scope != "US":
                continue
            job_id = clean(job.get("id"))
            rows.append({
                "external_job_id": job_id,
                "title": title,
                "normalized_title": normalize(title),
                "location": location,
                "category": "",
                "job_url": f"https://app.dover.com/apply/{slug}/{job_id}" if slug else source_url,
                "description_snippet": clean(job.get("workplace_type")),
                "market_scope": market_scope,
                "posted_text": "",
                "employment_type": clean(job.get("workplace_type")),
            })
        if not page.get("next"):
            break
        offset += 100
    return rows, requests, status


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--default-market", choices=("US", "unknown"), default="unknown")
    args = parser.parse_args()

    started = time.monotonic()
    rows, requests, status = rows_for(args.url)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({"status": "succeeded", "requests_count": requests,
                      "pages_fetched": requests, "raw_job_count": len(rows),
                      "parsed_job_count": len(rows), "duplicate_count": 0,
                      "last_http_status": status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


def _self_check() -> None:
    assert client_hint("https://app.dover.com/jobs/parade") == (None, "parade")
    assert client_hint("https://app.dover.com/Henry/careers/31981526-8af9-4a89-9f71-c96ef7f1cb5f/audit")[1] == "Henry"


if __name__ == "__main__":
    _self_check()
    raise SystemExit(main())
