#!/usr/bin/env python3
"""Resolve generic career pages into structured ATS candidate URLs.

Zero-Tavily-credit refinement: fetch retained generic_html pages and extract
outbound links to known ATS platforms. v2 also:
  - parses iframe/embed/data-* URLs
  - follows 1–3 same-host careers/jobs hops when the landing page has no ATS
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
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

from discover_career_sites import classify_url, company_tokens, excluded


CAREER_HINTS = re.compile(
    r"(job|jobs|career|careers|opening|openings|position|positions|opportunit|"
    r"workday|greenhouse|lever|ashby|icims|jobvite|workable|paylocity|rippling|"
    r"gusto|ultipro|eightfold|smartrecruiters|oracle|comeet|trinethire|brassring|"
    r"applytojob|catsone|trakstar|breezy|dover|phenom|dayforce|bamboohr|taleo|"
    r"recruitee|teamtailor|personio)",
    re.I,
)
SAME_SITE_HOP_HINTS = re.compile(
    r"(job|jobs|career|careers|opening|openings|position|positions|opportunit|"
    r"vacanc|hiring|join[-_ ]?us|work[-_ ]?with[-_ ]?us|search[-_ ]?jobs|"
    r"current[-_ ]?opening|view[-_ ]?opening|explore[-_ ]?role)",
    re.I,
)
SAME_SITE_HOP_PATH = re.compile(
    r"/(?:jobs?|careers?|openings?|positions?|opportunities|vacanc(?:y|ies)|"
    r"hiring|join-?us|work-with-us|search)(?:/|$|\?)",
    re.I,
)
URL_RE = re.compile(r"https?://[^\\\"'<> )\]]+")
ATTR_URL_KEYS = {
    "href", "src", "data-href", "data-url", "data-src", "data-apply-url",
    "data-job-url", "data-link", "data-board-url", "data-careers-url",
}
SUPPORTED_ATS_LINKS = {
    "greenhouse",
    "workday",
    "lever",
    "ashby",
    "smartrecruiters",
    "icims",
    "oracle_cloud",
    "workable",
    "jobvite",
    "paylocity",
    "rippling",
    "gusto",
    "phenom",
    "talentbrew",
    "brassring",
    "eightfold",
    "ultipro",
    "applytojob",
    "catsone",
    "trakstar",
    "breezy",
    "dover",
    "comeet",
    "trinethire",
}
STATIC_ASSET_RE = re.compile(r"\.(?:js|css|png|jpe?g|gif|svg|ico|woff2?|map|pdf)(?:[?#]|$)", re.I)
SKIP_HOP_RE = re.compile(
    r"(login|signin|sign-in|privacy|cookie|terms|mailto:|tel:|javascript:|"
    r"facebook\.com|twitter\.com|linkedin\.com|instagram\.com|youtube\.com)",
    re.I,
)


class PageLinkParser(HTMLParser):
    """Collect <a> text links plus iframe/embed/data-* URLs."""

    def __init__(self) -> None:
        super().__init__()
        self.anchor_links: list[tuple[str, str]] = []
        self.embed_urls: list[tuple[str, str]] = []
        self._current_href: str | None = None
        self._current_text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag_l = tag.lower()
        attrs_dict = {key.lower(): value for key, value in attrs if key and value}
        if tag_l == "a":
            href = attrs_dict.get("href")
            if href:
                self._current_href = href
                self._current_text = []
            return
        if tag_l in {"iframe", "embed", "frame", "object", "source", "link"}:
            for key in ATTR_URL_KEYS:
                value = attrs_dict.get(key)
                if value:
                    self.embed_urls.append((value, f"{tag_l}:{key}"))
        for key, value in attrs_dict.items():
            if key in ATTR_URL_KEYS and key not in {"href"} and value:
                # Catch data-* on buttons/divs without double-counting iframe src above.
                if tag_l not in {"iframe", "embed", "frame", "object", "source", "link", "a"}:
                    self.embed_urls.append((value, f"{tag_l}:{key}"))

    def handle_data(self, data: str) -> None:
        if self._current_href:
            self._current_text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a" and self._current_href:
            text = " ".join(piece.strip() for piece in self._current_text if piece.strip())
            self.anchor_links.append((self._current_href, html.unescape(text)[:300]))
            self._current_href = None
            self._current_text = []


def fetch_html(url: str, timeout: int) -> tuple[str, int]:
    request = Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 JobPushCareerResolver/1.1",
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
    if STATIC_ASSET_RE.search(absolute_url):
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
    if source_type in SUPPORTED_ATS_LINKS:
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


def same_host(url_a: str, url_b: str) -> bool:
    host_a = (urlsplit(url_a).hostname or "").casefold().removeprefix("www.")
    host_b = (urlsplit(url_b).hostname or "").casefold().removeprefix("www.")
    return bool(host_a and host_a == host_b)


def hop_score(source_url: str, href: str, anchor_text: str) -> float | None:
    absolute = urljoin(source_url, href)
    if not absolute.startswith(("http://", "https://")):
        return None
    if not same_host(source_url, absolute):
        return None
    if STATIC_ASSET_RE.search(absolute) or SKIP_HOP_RE.search(absolute):
        return None
    # Skip exact same page / fragment-only.
    if urlsplit(absolute)._replace(fragment="").geturl().rstrip("/") == \
       urlsplit(source_url)._replace(fragment="").geturl().rstrip("/"):
        return None
    text = f"{absolute} {anchor_text}"
    path = urlsplit(absolute).path or "/"
    score = 0.0
    if SAME_SITE_HOP_PATH.search(path):
        score += 40
    if SAME_SITE_HOP_HINTS.search(text):
        score += 25
    if score <= 0:
        return None
    # Prefer shorter listing paths over deep blog posts.
    score -= min(len(path) / 20.0, 8.0)
    return score


def extract_from_html(
    company_name: str,
    page_url: str,
    page_html: str,
) -> tuple[dict[str, dict], list[tuple[str, float]]]:
    parser_obj = PageLinkParser()
    parser_obj.feed(page_html)
    deduped: dict[str, dict] = {}
    hops: dict[str, float] = {}

    def consider_ats(href: str, label: str) -> None:
        candidate = score_candidate(company_name, page_url, href, label)
        if not candidate:
            return
        current = deduped.get(candidate["site_url"])
        if current is None or candidate["candidate_score"] > current["candidate_score"]:
            deduped[candidate["site_url"]] = candidate

    for href, anchor_text in parser_obj.anchor_links:
        consider_ats(href, anchor_text)
        score = hop_score(page_url, href, anchor_text)
        if score is not None:
            absolute = urljoin(page_url, href).split("#", 1)[0]
            hops[absolute] = max(hops.get(absolute, 0.0), score)

    for href, label in parser_obj.embed_urls:
        consider_ats(href, label)

    for raw_url in URL_RE.findall(page_html):
        consider_ats(html.unescape(raw_url), "embedded URL")

    ranked_hops = sorted(hops.items(), key=lambda item: item[1], reverse=True)
    return deduped, ranked_hops


def resolve_page_tree(
    company_name: str,
    source_url: str,
    timeout: int,
    max_candidates: int,
    max_hops: int,
) -> tuple[list[dict], str]:
    error_message = ""
    deduped: dict[str, dict] = {}
    visited: set[str] = set()
    queue: list[str] = [source_url]

    for depth in range(0, 2):  # landing page + one hop level
        next_queue: list[str] = []
        for page_url in queue:
            key = page_url.split("#", 1)[0].rstrip("/")
            if key in visited:
                continue
            visited.add(key)
            try:
                page_html, status = fetch_html(page_url, timeout)
            except HTTPError as exc:
                if depth == 0 and not error_message:
                    error_message = f"HTTPError {exc.code}"[:1000]
                continue
            except (URLError, TimeoutError, UnicodeDecodeError) as exc:
                if depth == 0 and not error_message:
                    error_message = f"{type(exc).__name__}: {exc}"[:1000]
                continue
            except Exception as exc:  # noqa: BLE001
                if depth == 0 and not error_message:
                    error_message = f"{type(exc).__name__}: {exc}"[:1000]
                continue

            if not page_html:
                if depth == 0 and not error_message:
                    error_message = f"non_html_or_empty_response status={status}"
                continue

            page_hits, hops = extract_from_html(company_name, page_url, page_html)
            for url, candidate in page_hits.items():
                # Prefer evidence that mentions hop origin when deeper.
                if depth > 0:
                    candidate = {
                        **candidate,
                        "evidence_snippet": (
                            f"Resolved via same-site hop from {source_url} -> {page_url}"
                        )[:1000],
                        "candidate_score": round(candidate["candidate_score"] + 3, 3),
                    }
                current = deduped.get(url)
                if current is None or candidate["candidate_score"] > current["candidate_score"]:
                    deduped[url] = candidate

            if depth == 0 and not deduped:
                for hop_url, _score in hops[:max_hops]:
                    hop_key = hop_url.split("#", 1)[0].rstrip("/")
                    if hop_key not in visited:
                        next_queue.append(hop_url)

        if deduped or depth > 0:
            break
        queue = next_queue
        if not queue:
            break

    found = sorted(deduped.values(), key=lambda item: item["candidate_score"], reverse=True)[
        :max_candidates
    ]
    return found, error_message


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
    parser.add_argument("--max-hops", type=int, default=3)
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
            found, error_message = resolve_page_tree(
                name,
                source_url,
                args.timeout,
                args.max_candidates,
                args.max_hops,
            )
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
