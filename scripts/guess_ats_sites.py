#!/usr/bin/env python3
"""Guess structured ATS career-site URLs without using a search API.

This is a zero-credit discovery step for companies that already have only
generic career-page candidates. It probes deterministic public ATS APIs for a
small set of likely company slugs and emits normal discovery-stage CSV files.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import socket
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from discover_career_sites import COMPANY_STOPWORDS, classify_url


PROVIDERS = ("greenhouse", "lever", "ashby", "smartrecruiters")
NOISE_HOST_LABELS = {
    "www", "jobs", "job", "careers", "career", "apply", "work", "join",
    "recruiting", "talent", "people", "hr",
}
GENERIC_SLUG_DENYLIST = {
    "international", "national", "global", "services", "systems", "technology",
    "technologies", "solutions", "consulting", "corporate", "company", "group",
    "capital", "health", "medical", "blue", "green", "new", "advanced",
    "staging", "test", "demo", "jobs", "careers", "career", "healthcare",
    "careeronestop", "obsglobal", "str", "glassdoor",
}


def clean_name(value: str) -> list[str]:
    value = re.sub(r"\b(dba|d/b/a|fka|formerly|aka)\b.*$", " ", value, flags=re.I)
    raw_tokens = re.findall(r"[a-z0-9]+", value.casefold())
    return [
        token
        for token in raw_tokens
        if len(token) > 1 and token not in COMPANY_STOPWORDS
    ]


def host_slug(host: str) -> str | None:
    host = host.casefold().removeprefix("www.")
    parts = [part for part in host.split(".") if part]
    if not parts:
        return None
    first = parts[0]
    if first in NOISE_HOST_LABELS and len(parts) > 1:
        first = parts[1]
    first = re.sub(r"[^a-z0-9]", "", first)
    if len(first) < 3 or first in NOISE_HOST_LABELS:
        return None
    return first


def slug_variants(company_name: str, generic_url: str, normalized_domain: str) -> list[str]:
    tokens = clean_name(company_name)
    variants: list[str] = []

    domains = []
    for value in (normalized_domain, urlparse(generic_url).netloc):
        if value:
            domain_slug = host_slug(value)
            if domain_slug:
                domains.append(domain_slug)

    if tokens:
        variants.extend([
            "".join(tokens),
            "-".join(tokens),
        ])
        if len(tokens) >= 2:
            variants.extend([
                "".join(tokens[:2]),
                "-".join(tokens[:2]),
            ])
    for domain_slug in domains:
        # Domain-derived aliases can recover cases like idbny/newscorp, but they
        # are noisy when Tavily retained the wrong generic page. Keep only
        # reasonably specific aliases or aliases that overlap with the employer
        # name. Short single-token aliases are left for human/site review.
        if len(domain_slug) >= 7 or any(token in domain_slug for token in tokens if len(token) >= 4):
            variants.append(domain_slug)

    seen = set()
    cleaned = []
    for variant in variants:
        variant = re.sub(r"[^a-z0-9-]", "", variant.casefold()).strip("-")
        if len(variant) < 3 or variant in seen or variant in GENERIC_SLUG_DENYLIST:
            continue
        seen.add(variant)
        cleaned.append(variant)
    return cleaned[:8]


def fetch_json(url: str, timeout: int) -> tuple[object | None, int, str | None]:
    request = Request(
        url,
        headers={
            "User-Agent": "JobPushATSGuesser/0.1",
            "Accept": "application/json,text/plain,*/*",
        },
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            raw = response.read(1_500_000)
            text = raw.decode(response.headers.get_content_charset() or "utf-8", errors="replace")
            try:
                return json.loads(text), response.status, None
            except json.JSONDecodeError as exc:
                return None, response.status, f"json_decode_error:{exc}"
    except HTTPError as exc:
        return None, exc.code, f"http_{exc.code}"
    except (TimeoutError, socket.timeout, URLError) as exc:
        return None, 0, f"{type(exc).__name__}:{exc}"


def validate_candidate(provider: str, slug: str, timeout: int) -> dict | None:
    if provider == "greenhouse":
        endpoint = f"https://boards-api.greenhouse.io/v1/boards/{slug}/jobs?content=false"
        site_url = f"https://job-boards.greenhouse.io/{slug}"
        payload, status, error = fetch_json(endpoint, timeout)
        ok = isinstance(payload, dict) and isinstance(payload.get("jobs"), list)
        job_count = len(payload.get("jobs", [])) if ok else 0
    elif provider == "lever":
        endpoint = f"https://api.lever.co/v0/postings/{slug}?mode=json"
        site_url = f"https://jobs.lever.co/{slug}"
        payload, status, error = fetch_json(endpoint, timeout)
        ok = isinstance(payload, list)
        job_count = len(payload) if ok else 0
    elif provider == "ashby":
        endpoint = f"https://api.ashbyhq.com/posting-api/job-board/{slug}?includeCompensation=false"
        site_url = f"https://jobs.ashbyhq.com/{slug}"
        payload, status, error = fetch_json(endpoint, timeout)
        ok = isinstance(payload, dict) and isinstance(payload.get("jobs"), list)
        job_count = len(payload.get("jobs", [])) if ok else 0
    elif provider == "smartrecruiters":
        endpoint = f"https://api.smartrecruiters.com/v1/companies/{slug}/postings?limit=1&offset=0"
        site_url = f"https://careers.smartrecruiters.com/{slug}"
        payload, status, error = fetch_json(endpoint, timeout)
        ok = isinstance(payload, dict) and ("content" in payload or "totalFound" in payload)
        job_count = int(payload.get("totalFound") or len(payload.get("content") or [])) if ok else 0
    else:
        return None

    # Some ATS APIs return a valid-looking empty board for slugs that are not
    # useful for crawling, and empty boards have a much higher mismatch risk
    # when guessed from noisy generic career pages. For automatic expansion we
    # only emit candidates that currently expose at least one posting.
    if not ok or job_count <= 0:
        return None
    canonical_url, host, site_kind, source_type, source_key = classify_url(site_url)
    score = 92.0 + min(job_count, 20) / 10
    return {
        "candidate_score": round(score, 3),
        "site_url": canonical_url[:2000],
        "normalized_domain": host[:500],
        "site_kind": site_kind,
        "source_type": source_type,
        "source_key": (source_key or "")[:500],
        "evidence_title": f"Validated {provider} slug '{slug}' via public API ({job_count} jobs)",
        "evidence_snippet": f"GET {endpoint} returned HTTP {status}; source=ats_url_guess",
        "provider": provider,
        "slug": slug,
        "job_count": job_count,
    }


def resolve_one(target: dict, providers: tuple[str, ...], timeout: int) -> tuple[dict, list[dict], str]:
    variants = slug_variants(
        target["canonical_name"],
        target.get("site_url", ""),
        target.get("normalized_domain", ""),
    )
    found: dict[str, dict] = {}
    errors = 0
    for slug in variants:
        for provider in providers:
            candidate = validate_candidate(provider, slug, timeout)
            if candidate:
                current = found.get(candidate["site_url"])
                if current is None or candidate["candidate_score"] > current["candidate_score"]:
                    found[candidate["site_url"]] = candidate
            else:
                errors += 1
    candidates = sorted(found.values(), key=lambda row: row["candidate_score"], reverse=True)
    error_message = "" if candidates else f"no_valid_ats_guess variants={','.join(variants[:8])} probes={errors}"
    return target, candidates[:3], error_message[:1000]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("targets_csv")
    parser.add_argument("candidates_csv")
    parser.add_argument("results_csv")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--providers", default=",".join(PROVIDERS))
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--timeout", type=int, default=6)
    args = parser.parse_args()

    providers = tuple(
        provider.strip()
        for provider in args.providers.split(",")
        if provider.strip() in PROVIDERS
    )
    if not providers:
        raise SystemExit("No supported providers selected")

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

        with ThreadPoolExecutor(max_workers=max(args.workers, 1)) as executor:
            futures = {
                executor.submit(resolve_one, target, providers, args.timeout): index
                for index, target in enumerate(targets, start=1)
            }
            for future in as_completed(futures):
                index = futures[future]
                target, candidates, error_message = future.result()
                query = f"guess ATS URLs from company name/domain using {','.join(providers)}"
                for rank, candidate in enumerate(candidates, start=1):
                    row = {key: candidate[key] for key in candidate_fields if key in candidate}
                    row.update({
                        "run_id": args.run_id,
                        "consolidation_key": target["consolidation_key"],
                        "canonical_name": target["canonical_name"],
                        "search_query": query,
                        "candidate_rank": rank,
                    })
                    candidate_writer.writerow(row)
                result_writer.writerow({
                    "run_id": args.run_id,
                    "consolidation_key": target["consolidation_key"],
                    "canonical_name": target["canonical_name"],
                    "search_query": query,
                    "search_succeeded": "true",
                    "candidate_count": len(candidates),
                    "error_message": "" if candidates else error_message,
                })
                print(
                    f"[{index}/{len(targets)}] {target['canonical_name']}: {len(candidates)} guesses",
                    flush=True,
                )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
