#!/usr/bin/env python3
"""Fetch every result page from a public iCIMS search and emit normalized CSV."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from dataclasses import dataclass, asdict
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen


USER_AGENT = "JobPush/0.1 (+public-career-site-monitor; contact=repository-owner)"


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(value)).strip()


def normalize_title(value: str) -> str:
    value = clean_text(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def canonical_job_url(value: str) -> str:
    parts = urlsplit(html.unescape(value))
    query = [(key, val) for key, val in parse_qsl(parts.query) if key != "in_iframe"]
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), ""))


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


class ICIMSParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.jobs: list[Job] = []
        self.total_pages = 1
        self._card_depth = 0
        self._capture: str | None = None
        self._buffer: list[str] = []
        self._current: dict[str, str] = {}
        self._field_name = ""
        self.location_options: list[tuple[str, str]] = []
        self._in_location_select = False
        self._option_value: str | None = None

    @staticmethod
    def _classes(attrs: list[tuple[str, str | None]]) -> set[str]:
        return set(dict(attrs).get("class", "").split())

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr = dict(attrs)
        classes = self._classes(attrs)
        if tag == "select" and attr.get("name") == "searchLocation":
            self._in_location_select = True
        elif tag == "option" and self._in_location_select:
            self._option_value = attr.get("value")
            self._capture = "location_option"
            self._buffer = []
        if tag == "li" and "iCIMS_JobCardItem" in classes:
            self._card_depth = 1
            self._current = {}
            return
        if self._card_depth:
            self._card_depth += 1
            if tag == "div" and {"header", "left"}.issubset(classes):
                self._capture = "location"
                self._buffer = []
            elif tag == "a" and "iCIMS_Anchor" in classes and "/jobs/" in attr.get("href", ""):
                self._current["job_url"] = canonical_job_url(attr["href"])
                match = re.search(r"/jobs/(\d+)/", attr["href"])
                if match:
                    self._current["external_job_id"] = match.group(1)
            elif tag == "h3":
                self._capture = "title"
                self._buffer = []
            elif tag == "div" and "description" in classes:
                self._capture = "description_snippet"
                self._buffer = []
            elif tag == "dt" and "iCIMS_JobHeaderField" in classes:
                self._capture = "field_name"
                self._buffer = []
            elif tag == "dd" and "iCIMS_JobHeaderData" in classes:
                self._capture = "field_value"
                self._buffer = []

        if tag == "a" and "/jobs/search?" in attr.get("href", ""):
            query = dict(parse_qsl(urlsplit(html.unescape(attr["href"])).query))
            if query.get("pr", "").isdigit():
                self.total_pages = max(self.total_pages, int(query["pr"]) + 1)

    def handle_endtag(self, tag: str) -> None:
        if self._capture == "location_option" and tag == "option":
            label = clean_text("".join(self._buffer))
            if self._option_value:
                self.location_options.append((self._option_value, label))
            self._capture = None
            self._buffer = []
            self._option_value = None
        if tag == "select" and self._in_location_select:
            self._in_location_select = False
        if not self._card_depth:
            return
        if self._capture and (
            (self._capture == "title" and tag == "h3")
            or (self._capture in {"location", "description_snippet"} and tag == "div")
            or (self._capture == "field_name" and tag == "dt")
            or (self._capture == "field_value" and tag == "dd")
        ):
            value = clean_text("".join(self._buffer))
            if self._capture == "field_name":
                self._field_name = value
            elif self._capture == "field_value":
                if self._field_name == "Category":
                    self._current["category"] = value
                elif self._field_name == "Requisition ID" and not self._current.get("external_job_id"):
                    self._current["external_job_id"] = value
            else:
                if self._capture == "location":
                    value = re.sub(r"^Job Locations?\s+", "", value, flags=re.IGNORECASE)
                self._current[self._capture] = value
            self._capture = None
            self._buffer = []
        self._card_depth -= 1
        if self._card_depth == 0 and tag == "li":
            if self._current.get("external_job_id") and self._current.get("title"):
                self.jobs.append(
                    Job(
                        external_job_id=self._current["external_job_id"],
                        title=self._current["title"],
                        normalized_title=normalize_title(self._current["title"]),
                        location=self._current.get("location", ""),
                        category=self._current.get("category", ""),
                        job_url=self._current.get("job_url", ""),
                        description_snippet=self._current.get("description_snippet", ""),
                    )
                )

    def handle_data(self, data: str) -> None:
        if self._capture:
            self._buffer.append(data)


def page_url(search_url: str, page: int, extra_query: list[tuple[str, str]] | None = None) -> str:
    parts = urlsplit(search_url)
    query = [(key, value) for key, value in parse_qsl(parts.query)
             if key not in {"pr", "in_iframe", "searchLocation"}]
    query.extend(extra_query or [])
    query.extend([("pr", str(page)), ("in_iframe", "1")])
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), ""))


def fetch(url: str, timeout: int) -> tuple[str, int]:
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html"})
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode(response.headers.get_content_charset() or "utf-8", "replace"), response.status


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--delay", type=float, default=0.5)
    parser.add_argument("--country", choices=("US",))
    args = parser.parse_args()

    started = time.monotonic()
    requests_count = 0
    statuses: list[int] = []
    all_jobs: dict[str, Job] = {}
    raw_job_count = 0

    first_html, status = fetch(page_url(args.url, 0), args.timeout)
    requests_count += 1
    statuses.append(status)
    first = ICIMSParser()
    first.feed(first_html)
    scope_query: list[tuple[str, str]] = []
    if args.country == "US":
        scope_query = [("searchLocation", value) for value, label in first.location_options
                       if label.casefold().startswith("united states-")]
        if not scope_query:
            raise RuntimeError("iCIMS page did not expose a United States location option")
        first_html, status = fetch(page_url(args.url, 0, scope_query), args.timeout)
        requests_count += 1
        statuses.append(status)
        first = ICIMSParser()
        first.feed(first_html)
    raw_job_count += len(first.jobs)
    for job in first.jobs:
        all_jobs[job.external_job_id] = job

    for page in range(1, first.total_pages):
        time.sleep(args.delay)
        body, status = fetch(page_url(args.url, page, scope_query), args.timeout)
        requests_count += 1
        statuses.append(status)
        current = ICIMSParser()
        current.feed(body)
        raw_job_count += len(current.jobs)
        for job in current.jobs:
            all_jobs[job.external_job_id] = job

    args.output.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(Job.__dataclass_fields__)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for job in all_jobs.values():
            writer.writerow(asdict(job))

    print(json.dumps({
        "status": "succeeded",
        "requests_count": requests_count,
        "pages_fetched": first.total_pages,
        "raw_job_count": raw_job_count,
        "parsed_job_count": len(all_jobs),
        "duplicate_count": raw_job_count - len(all_jobs),
        "last_http_status": statuses[-1],
        "latency_ms": round((time.monotonic() - started) * 1000),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
