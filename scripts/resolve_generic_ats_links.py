#!/usr/bin/env python3
"""Resolve generic career pages into structured ATS candidate URLs.

This is a zero-Tavily-credit refinement step. It fetches already-retained
generic HTML candidate pages and looks for outbound links to known ATS/job
platforms. The output matches `career_site_discovery_stage` so the DB runner
can load the findings as ordinary candidates with `discovery_source` set to
`generic_html_link_resolver`.
"""

from __future__ import annotations

import argparse
import csv
import html
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen

from discover_career_sites import classify_url, company_tokens, excluded


CAREER_HINTS = re.compile(
    r"(job|jobs|career|careers|opening|openings|position|positions|opportunit|workday|greenhouse|lever|ashby|icims|jobvite|workable|paylocity|rippling|ultipro)",
    re.I,
)


class LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str]] = []
        self._current_href: str | None = None
        self._current_text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        attrs_dict = {key.lower(): value for key, value in attrs if key}
        href = attrs_dict.get("href")
        if href:
            self._current_href = href
            self._current_text = []

    def handle_data(self, data: str) -> None:
        if self._current_href:
            self._current_text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a" and self._current_href:
            text = " ".join(piece.strip() for piece in self._current_text if piece.strip())
            self.links.append((self._current_href, html.unescape(text)[:300]))
            self._current_href = None
            self._current_text = []


def fetch_html(url: str, timeout: int) -> tuple[str, int]:
    request = Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 JobPushCareerResolver/1.0",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
    )
    with urlopen(request, timeout=timeout) as response:
        content_type = response.headers.get("content-type", "")
        if "text/html" not in content_type and "application/xhtml" not in content_type:
            return "", response.status
        raw = response.read(1_500_000)
        charset = response.headers.get_content_charset() or "utf-8"
        return raw.decode(charset, errors="replace"), response.status


def score_candidate(company_name: str, source_url: str, href: str, anchor_text: str) -> dict | None:
    absolute_url = urljoin(source_url, href)
    if not absolute_url.startswith(("http://", "https://")):
        return None
    canonical_url, host, site_kind, source_type, source_key = classify_url(absolute_url)
    if not host or excluded(host) or source_type == "generic_html":
        return None

    text = f"{absolute_url} {anchor_text}".casefold()
    tokens = company_tokens(company_name)
    score = 65.0
    if CAREER_HINTS.search(text):
        score += 15
    if tokens and any(token in text for token in tokens[:4]):
        score += 10
    if source_type in {"greenhouse", "workday", "lever", "ashby", "smartrecruiters", "icims"}:
        score += 10

    return {
        "candidate_score": round(score, 3),
        "site_url": canonical_url[:2000],
        "normalized_domain": host[:500],
        "site_kind": site_kind,
        "source_type": source_type,
        "source_key": (source_key or "")[:500],
        "evidence_title": (anchor_text or f"Resolved ATS link from {source_url}")[:500],
        "evidence_snippet": f"Resolved from generic candidate: {source_url}"[:1000],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("targets_csv")
    parser.add_argument("candidates_csv")
    parser.add_argument("results_csv")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--delay", type=float, default=0.0)
    parser.add_argument("--timeout", type=int, default=8)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--max-candidates", type=int, default=3)
    args = parser.parse_args()

    with open(args.targets_csv, newline="", encoding="utf-8") as source:
        targets = list(csv.DictReader(source))

    candidate_fields = [
        "run_id", "consolidation_key", "canonical_name", "search_query",
        "candidate_rank", "candidate_score", "site_url", "normalized_domain",
        "site_kind", "source_type", "source_key", "evidence_title", "evidence_snippet",
    ]
    result_fields = [
        "run_id", "consolidation_key", "canonical_name", "search_query",
        "search_succeeded", "candidate_count", "error_message",
    ]

    with (
        open(args.candidates_csv, "w", newline="", encoding="utf-8") as candidates_file,
        open(args.results_csv, "w", newline="", encoding="utf-8") as results_file,
    ):
        candidate_writer = csv.DictWriter(candidates_file, fieldnames=candidate_fields)
        result_writer = csv.DictWriter(results_file, fieldnames=result_fields)
        candidate_writer.writeheader()
        result_writer.writeheader()

        def resolve_one(index: int, target: dict) -> tuple[int, dict, list[dict], str]:
            name = target["canonical_name"].strip()
            source_url = target["site_url"].strip()
            error_message = ""
            found: list[dict] = []
            try:
                page_html, status = fetch_html(source_url, args.timeout)
                if not page_html:
                    error_message = f"non_html_or_empty_response status={status}"
                else:
                    parser_obj = LinkParser()
                    parser_obj.feed(page_html)
                    deduped: dict[str, dict] = {}
                    for href, anchor_text in parser_obj.links:
                        candidate = score_candidate(name, source_url, href, anchor_text)
                        if not candidate:
                            continue
                        current = deduped.get(candidate["site_url"])
                        if current is None or candidate["candidate_score"] > current["candidate_score"]:
                            deduped[candidate["site_url"]] = candidate
                    found = sorted(
                        deduped.values(), key=lambda item: item["candidate_score"], reverse=True
                    )[: args.max_candidates]
            except HTTPError as exc:
                error_message = f"HTTPError {exc.code}"[:1000]
            except (URLError, TimeoutError, UnicodeDecodeError) as exc:
                error_message = f"{type(exc).__name__}: {exc}"[:1000]
            except Exception as exc:  # noqa: BLE001
                error_message = f"{type(exc).__name__}: {exc}"[:1000]
            return index, target, found, error_message

        with ThreadPoolExecutor(max_workers=max(1, args.workers)) as executor:
            futures = {
                executor.submit(resolve_one, index, target): (index, target)
                for index, target in enumerate(targets, start=1)
            }
            for future in as_completed(futures):
                index, target, found, error_message = future.result()
                name = target["canonical_name"].strip()
                source_url = target["site_url"].strip()
                search_query = f"resolve structured ATS links from {source_url}"
                for rank, candidate in enumerate(found, start=1):
                    candidate_writer.writerow({
                        "run_id": args.run_id,
                        "consolidation_key": target["consolidation_key"],
                        "canonical_name": name,
                        "search_query": search_query,
                        "candidate_rank": rank,
                        **candidate,
                    })
                result_writer.writerow({
                    "run_id": args.run_id,
                    "consolidation_key": target["consolidation_key"],
                    "canonical_name": name,
                    "search_query": search_query,
                    "search_succeeded": "false" if error_message else "true",
                    "candidate_count": len(found),
                    "error_message": error_message,
                })
                print(f"[{index}/{len(targets)}] {name}: {len(found)} ATS links", flush=True)
                if args.delay:
                    time.sleep(args.delay)


if __name__ == "__main__":
    main()
