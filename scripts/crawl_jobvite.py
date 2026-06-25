#!/usr/bin/env python3
"""Fetch Jobvite career boards from public HTML + JobPosting JSON-LD."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from html.parser import HTMLParser
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


def board_token(url: str) -> str:
    parts = [part for part in urlsplit(url).path.split("/") if part]
    if len(parts) >= 2 and parts[0] == "careers":
        return parts[1]
    if parts:
        return parts[0]
    raise ValueError(f"Cannot derive Jobvite token from {url}")


class JobviteListParser(HTMLParser):
    def __init__(self, token: str, base_url: str) -> None:
        super().__init__()
        self.token = token
        self.base_url = base_url
        self.links: dict[str, str] = {}
        self._href: str | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        attrs_dict = {key.lower(): value for key, value in attrs if key}
        href = attrs_dict.get("href") or ""
        if re.search(rf"/{re.escape(self.token)}/job/[A-Za-z0-9]+", href):
            self._href = href
            self._text = []

    def handle_data(self, data: str) -> None:
        if self._href:
            self._text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a" and self._href:
            title = clean(" ".join(self._text))
            if title:
                self.links[urljoin(self.base_url, self._href)] = title
            self._href = None
            self._text = []


def fetch_text(url: str, accept: str = "text/html") -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": "JobPush/0.1", "Accept": accept})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace"), response.status


def extract_json_ld_job(html_text: str) -> dict:
    for match in re.finditer(
        r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        html_text,
        re.S | re.I,
    ):
        raw = clean(match.group(1))
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            continue
        candidates = payload if isinstance(payload, list) else [payload]
        for item in candidates:
            if isinstance(item, dict) and item.get("@type") == "JobPosting":
                return item
    return {}


def location_from_json_ld(job: dict) -> str:
    locations = job.get("jobLocation") or []
    if isinstance(locations, dict):
        locations = [locations]
    names = []
    for location in locations:
        address = (location or {}).get("address") or {}
        pieces = [
            address.get("addressLocality"),
            address.get("addressRegion"),
            address.get("addressCountry"),
        ]
        value = clean(", ".join(str(piece) for piece in pieces if piece))
        if value:
            names.append(value)
    return "; ".join(names)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    args = ap.parse_args()

    started = time.monotonic()
    token = board_token(args.url)
    list_url = f"https://jobs.jobvite.com/{token}/jobs"
    list_html, status = fetch_text(list_url)
    parser = JobviteListParser(token, list_url)
    parser.feed(list_html)

    rows = []
    requests_count = 1
    for job_url, fallback_title in parser.links.items():
        detail_html, _detail_status = fetch_text(job_url)
        requests_count += 1
        job = extract_json_ld_job(detail_html)
        title = clean(job.get("title")) or fallback_title
        location = location_from_json_ld(job)
        employment_type = clean(job.get("employmentType"))
        description = strip_html(job.get("description"))
        external_id = urlsplit(job_url).path.rstrip("/").split("/")[-1]
        rows.append({
            "external_job_id": external_id,
            "title": title,
            "normalized_title": normalize(title),
            "location": location,
            "category": "",
            "job_url": job_url,
            "description_snippet": description[:1000],
            "market_scope": classify_market_scope(location, args.default_market),
            "posted_text": clean(job.get("datePosted")),
            "employment_type": employment_type,
        })

    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps({"status": "succeeded", "requests_count": requests_count, "pages_fetched": requests_count,
                      "raw_job_count": len(rows), "parsed_job_count": len(rows),
                      "duplicate_count": 0, "last_http_status": status,
                      "latency_ms": round((time.monotonic() - started) * 1000)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
