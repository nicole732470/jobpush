#!/usr/bin/env python3
"""Fetch a Gusto public job board."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from dataclasses import asdict, dataclass
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

from market_scope import classify_market_scope


FIELDS = ["external_job_id", "title", "normalized_title", "location", "category",
          "job_url", "description_snippet", "market_scope", "posted_text", "employment_type"]


def clean(value: str | None) -> str:
    return re.sub(r"\s+", " ", html.unescape(value or "")).strip()


def normalize(value: str) -> str:
    value = clean(value).casefold()
    value = re.sub(r"[^\w+#./-]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


@dataclass
class Posting:
    href: str
    title: str
    text: str


class GustoBoardParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.postings: list[Posting] = []
        self._href = ""
        self._data: list[str] = []
        self._in_h3 = False
        self._title: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = {key.lower(): value for key, value in attrs if key}
        if tag.lower() == "a" and (attrs_dict.get("href") or "").startswith("/postings/"):
            self._href = attrs_dict["href"] or ""
            self._data = []
            self._title = []
        elif self._href and tag.lower() == "h3":
            self._in_h3 = True

    def handle_data(self, data: str) -> None:
        if not self._href:
            return
        self._data.append(data)
        if self._in_h3:
            self._title.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "h3":
            self._in_h3 = False
        elif tag.lower() == "a" and self._href:
            title = clean(" ".join(self._title))
            if title:
                self.postings.append(Posting(self._href, title, clean(" ".join(self._data))))
            self._href = ""
            self._data = []
            self._title = []


def fetch(url: str, timeout: int) -> tuple[str, int]:
    request = Request(url, headers={
        "User-Agent": "Mozilla/5.0 JobPush/0.1",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
    })
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode(response.headers.get_content_charset() or "utf-8", "replace"), response.status


def external_id(href: str) -> str:
    return urlsplit(href).path.rsplit("/", 1)[-1]


def location_from_text(posting: Posting) -> str:
    text = posting.text.removeprefix(posting.title).strip()
    text = re.split(r"\$|·|Full time|Part time|Intern|Contract", text, maxsplit=1, flags=re.I)[0]
    return clean(text)


def employment_type_from_text(text: str) -> str:
    match = re.search(r"\b(Full time|Part time|Intern|Contract)\b", text, re.I)
    return clean(match.group(1)) if match else ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=15)
    parser.add_argument("--default-market", choices=("US", "non-US", "unknown"), default="unknown")
    args = parser.parse_args()

    started = time.monotonic()
    body, status = fetch(args.url, args.timeout)
    parser_obj = GustoBoardParser()
    parser_obj.feed(body)

    rows = []
    seen = set()
    for posting in parser_obj.postings:
        job_url = urljoin(args.url, posting.href)
        job_id = external_id(posting.href)
        if not job_id or job_id in seen:
            continue
        seen.add(job_id)
        location = location_from_text(posting)
        rows.append({
            "external_job_id": job_id,
            "title": posting.title,
            "normalized_title": normalize(posting.title),
            "location": location,
            "category": "",
            "job_url": job_url,
            "description_snippet": "",
            "market_scope": classify_market_scope(location, args.default_market),
            "posted_text": "",
            "employment_type": employment_type_from_text(posting.text),
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
