#!/usr/bin/env python3
"""Find career-site candidates with one basic Tavily search per company."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse, urlunparse
from urllib.request import Request, urlopen


EXCLUDED_DOMAINS = {
    "linkedin.com", "indeed.com", "glassdoor.com", "ziprecruiter.com",
    "monster.com", "careerbuilder.com", "simplyhired.com", "theladders.com",
    "wikipedia.org", "crunchbase.com", "bloomberg.com", "reuters.com",
    "facebook.com", "instagram.com", "x.com", "youtube.com",
    "builtin.com", "builtinchicago.org", "builtinnyc.com", "naukri.com",
    "virtualvocations.com", "flexjobs.com", "career.com", "instahyre.com",
    "remoterocketship.com", "levels.fyi", "dice.com", "latinograduate.com",
    "hirebase.org", "6amcity.com", "insidehighered.com", "nena.org", "acams.org",
}
COMPANY_STOPWORDS = {
    "inc", "incorporated", "llc", "ltd", "limited", "corp", "corporation",
    "company", "companies", "co", "group", "holdings", "the", "plc",
}
CAREER_TERMS = ("career", "careers", "jobs", "job", "join", "opportunities", "openings")


def company_tokens(name):
    return [
        token for token in re.findall(r"[a-z0-9]+", name.casefold())
        if len(token) > 2 and token not in COMPANY_STOPWORDS
    ]


def excluded(host):
    return any(host == domain or host.endswith(f".{domain}") for domain in EXCLUDED_DOMAINS)


def classify_url(raw_url):
    parsed = urlparse(raw_url)
    host = parsed.netloc.casefold().split(":", 1)[0].removeprefix("www.")
    path_parts = [part for part in parsed.path.split("/") if part]
    source_type = "generic_html"
    source_key = None
    site_kind = "careers"
    canonical_path = parsed.path.rstrip("/") or "/"

    if host in {"boards.greenhouse.io", "job-boards.greenhouse.io"} and path_parts:
        source_type, source_key, site_kind = "greenhouse", path_parts[0], "ats_feed"
        canonical_path = f"/{source_key}"
    elif host in {"jobs.lever.co", "jobs.eu.lever.co"} and path_parts:
        source_type, source_key, site_kind = "lever", path_parts[0], "ats_feed"
        canonical_path = f"/{source_key}"
    elif host == "jobs.ashbyhq.com" and path_parts:
        source_type, source_key, site_kind = "ashby", path_parts[0], "ats_feed"
        canonical_path = f"/{source_key}"
    elif host == "careers.smartrecruiters.com" and path_parts:
        source_type, source_key, site_kind = "smartrecruiters", path_parts[0], "ats_feed"
        canonical_path = f"/{source_key}"
    elif host.endswith("myworkdayjobs.com"):
        source_type, source_key, site_kind = "workday", host, "ats_feed"
    elif host.endswith("icims.com"):
        source_type, source_key, site_kind = "icims", host, "ats_feed"
    elif host.endswith("successfactors.com"):
        source_type, source_key, site_kind = "successfactors", host, "ats_feed"
    elif not any(term in parsed.path.casefold() for term in CAREER_TERMS):
        site_kind = "corporate"

    canonical_url = urlunparse((parsed.scheme or "https", parsed.netloc, canonical_path, "", "", ""))
    return canonical_url, host, site_kind, source_type, source_key


def candidate_score(company_name, row):
    url = str(row.get("url") or "").strip()
    title = str(row.get("title") or "").strip()
    if not url.startswith(("http://", "https://")):
        return None
    canonical_url, host, site_kind, source_type, source_key = classify_url(url)
    if not host or excluded(host):
        return None

    title_lower = title.casefold()
    path_lower = urlparse(url).path.casefold()
    score = max(0.0, min(float(row.get("score") or 0), 1.0)) * 20
    if source_type != "generic_html":
        score += 50
    if any(term in path_lower for term in CAREER_TERMS):
        score += 25
    if any(term in title_lower for term in CAREER_TERMS):
        score += 15
    tokens = company_tokens(company_name)
    if tokens and any(token in host or token in title_lower for token in tokens[:4]):
        score += 15
    if "official" in title_lower:
        score += 5
    if site_kind == "corporate":
        score -= 15
    if score < 25:
        return None
    return {
        "candidate_score": round(score, 3),
        "site_url": canonical_url[:2000],
        "normalized_domain": host[:500],
        "site_kind": site_kind,
        "source_type": source_type,
        "source_key": (source_key or "")[:500],
        "evidence_title": title[:500],
        "evidence_snippet": str(row.get("content") or "").strip()[:1000],
    }


def tavily_search(api_key, query, max_results):
    payload = json.dumps({
        "api_key": api_key,
        "query": query,
        "search_depth": "basic",
        "max_results": max_results,
        "include_answer": False,
        "include_raw_content": False,
        "topic": "general",
    }).encode()
    request = Request(
        "https://api.tavily.com/search",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("targets_csv")
    parser.add_argument("candidates_csv")
    parser.add_argument("results_csv")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--max-results", type=int, default=6)
    parser.add_argument("--max-candidates", type=int, default=3)
    parser.add_argument("--delay", type=float, default=0.2)
    args = parser.parse_args()

    api_key = os.environ.get("TAVILY_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("TAVILY_API_KEY is required")

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

        for index, target in enumerate(targets, start=1):
            name = target["canonical_name"].strip()
            query = f'"{name}" official careers jobs'
            error_message = ""
            found = []
            try:
                data = tavily_search(api_key, query, args.max_results)
                deduped = {}
                for row in data.get("results") or []:
                    candidate = candidate_score(name, row)
                    if not candidate:
                        continue
                    current = deduped.get(candidate["site_url"])
                    if current is None or candidate["candidate_score"] > current["candidate_score"]:
                        deduped[candidate["site_url"]] = candidate
                found = sorted(
                    deduped.values(), key=lambda item: item["candidate_score"], reverse=True
                )[: args.max_candidates]
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
                error_message = f"{type(exc).__name__}: {exc}"[:1000]
            except Exception as exc:  # noqa: BLE001
                error_message = f"{type(exc).__name__}: {exc}"[:1000]

            for rank, candidate in enumerate(found, start=1):
                candidate_writer.writerow({
                    "run_id": args.run_id,
                    "consolidation_key": target["consolidation_key"],
                    "canonical_name": name,
                    "search_query": query,
                    "candidate_rank": rank,
                    **candidate,
                })
            result_writer.writerow({
                "run_id": args.run_id,
                "consolidation_key": target["consolidation_key"],
                "canonical_name": name,
                "search_query": query,
                "search_succeeded": "false" if error_message else "true",
                "candidate_count": len(found),
                "error_message": error_message,
            })
            print(f"[{index}/{len(targets)}] {name}: {len(found)} candidates", flush=True)
            if index < len(targets) and args.delay:
                time.sleep(args.delay)


if __name__ == "__main__":
    main()
