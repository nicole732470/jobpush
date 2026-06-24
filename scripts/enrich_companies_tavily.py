#!/usr/bin/env python3
"""Collect a small, auditable Tavily company-profile pilot.

The script intentionally does not invent structured attributes from prose.  It
stores Tavily's answer, sources, and full raw response for later rule design and
human verification.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import time
from pathlib import Path
from urllib.request import Request, urlopen


def sql_literal(value: object) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def pg_text_array(values: list[str]) -> str:
    if not values:
        return "'{}'::text[]"
    return "ARRAY[" + ",".join(sql_literal(value) for value in values) + "]::text[]"


def search(api_key: str, company_name: str) -> tuple[str, dict[str, object]]:
    query = (
        f'"{company_name}" company profile: official website, primary industry, '
        "headquarters, approximate employee count, founded year, ownership type, "
        "and a one-sentence description. Prefer official company sources."
    )
    payload = {
        "api_key": api_key,
        "query": query,
        "search_depth": "basic",
        "max_results": 6,
        "include_answer": "basic",
        "include_raw_content": False,
        "topic": "general",
    }
    request = Request(
        "https://api.tavily.com/search",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=45) as response:
        return query, json.load(response)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_csv")
    parser.add_argument("output_sql")
    parser.add_argument("--delay", type=float, default=0.2)
    args = parser.parse_args()

    api_key = os.environ.get("TAVILY_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("TAVILY_API_KEY is required")

    with open(args.input_csv, newline="", encoding="utf-8") as handle:
        companies = list(csv.DictReader(handle))

    statements = ["BEGIN;"]
    for index, company in enumerate(companies, start=1):
        key = company["consolidation_key"]
        name = company["canonical_name"]
        query, response = search(api_key, name)
        answer = str(response.get("answer") or "").strip() or None
        urls = []
        for result in response.get("results") or []:
            url = str(result.get("url") or "").strip()
            if url and url not in urls:
                urls.append(url)
        raw = json.dumps(response, ensure_ascii=False, separators=(",", ":"))
        statements.append(
            "INSERT INTO jobpush.company_external_enrichment ("
            "consolidation_key, company_description, source_urls, source_provider, "
            "source_query, raw_response, extraction_method, review_status, researched_at, updated_at"
            ") VALUES ("
            f"{sql_literal(key)}, {sql_literal(answer)}, {pg_text_array(urls)}, 'tavily', "
            f"{sql_literal(query)}, {sql_literal(raw)}::jsonb, "
            "'tavily-basic-answer-v1', 'unreviewed', now(), now()"
            ") ON CONFLICT (consolidation_key) DO UPDATE SET "
            "company_description = EXCLUDED.company_description, "
            "source_urls = EXCLUDED.source_urls, source_provider = EXCLUDED.source_provider, "
            "source_query = EXCLUDED.source_query, raw_response = EXCLUDED.raw_response, "
            "extraction_method = EXCLUDED.extraction_method, review_status = 'unreviewed', "
            "researched_at = EXCLUDED.researched_at, updated_at = now();"
        )
        print(f"[{index}/{len(companies)}] {name}: {len(urls)} sources", flush=True)
        if index < len(companies) and args.delay:
            time.sleep(args.delay)
    statements.append("COMMIT;")
    Path(args.output_sql).write_text("\n".join(statements) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
