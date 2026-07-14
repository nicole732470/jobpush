#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import html
from html.parser import HTMLParser
import json
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen


SKIP_TAGS = {"script", "style", "nav", "footer", "header", "aside", "noscript", "svg"}
JD_HINTS = ("job-description", "jobdescription", "job_description", "description", "job-details", "jobdetails")


def clean_text(value: str) -> str:
    value = html.unescape(re.sub(r"<[^>]+>", " ", value or ""))
    value = re.sub(r"[\t\r ]+", " ", value)
    value = re.sub(r" *\n+ *", "\n", value)
    return value.strip()


def json_objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from json_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from json_objects(child)


class JobPageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.capture_depth = 0
        self.body: list[str] = []
        self.captured: list[str] = []
        self.ld_json: list[str] = []
        self.embedded_json: list[str] = []
        self.script_kind = ""
        self.script_parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in SKIP_TAGS:
            if tag == "script":
                script_type = (attrs.get("type") or "").lower()
                script_id = (attrs.get("id") or "").lower()
                if "ld+json" in script_type:
                    self.script_kind = "ld"
                elif script_id == "__next_data__" or "json" in script_type:
                    self.script_kind = "embedded"
                else:
                    self.script_kind = ""
                self.script_parts = []
            self.skip_depth += 1
            return
        marker = " ".join((attrs.get("id") or "", attrs.get("class") or "")).lower()
        if any(hint in marker for hint in JD_HINTS):
            self.capture_depth += 1
        elif self.capture_depth:
            self.capture_depth += 1
        if tag in {"p", "br", "li", "div", "section", "h1", "h2", "h3"}:
            self.body.append("\n")
            if self.capture_depth:
                self.captured.append("\n")

    def handle_endtag(self, tag):
        if tag in SKIP_TAGS:
            if tag == "script" and self.script_kind:
                value = "".join(self.script_parts).strip()
                (self.ld_json if self.script_kind == "ld" else self.embedded_json).append(value)
                self.script_kind = ""
            self.skip_depth = max(0, self.skip_depth - 1)
            return
        if self.capture_depth:
            self.capture_depth -= 1

    def handle_data(self, data):
        if self.skip_depth:
            if self.script_kind:
                self.script_parts.append(data)
            return
        self.body.append(data)
        if self.capture_depth:
            self.captured.append(data)


def parse_json(value: str):
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return None


def structured_fields(parser: JobPageParser) -> dict:
    candidates = []
    for raw in parser.ld_json:
        parsed = parse_json(raw)
        if parsed is not None:
            candidates.extend(json_objects(parsed))
    job = next((obj for obj in candidates if str(obj.get("@type", "")).lower() == "jobposting"), {})

    description = clean_text(str(job.get("description") or ""))
    if len(description) < 200:
        for raw in parser.embedded_json:
            parsed = parse_json(raw)
            if parsed is None:
                continue
            values = []
            for obj in json_objects(parsed):
                for key in ("descriptionHtml", "description", "job_description", "content"):
                    text = clean_text(str(obj.get(key) or ""))
                    if len(text) >= 200:
                        values.append(text)
            if values:
                description = max(values, key=len)
                break

    if len(description) < 200:
        captured = clean_text("".join(parser.captured))
        body = clean_text("".join(parser.body))
        description = captured if len(captured) >= 200 else body

    salary = job.get("baseSalary")
    salary_text = json.dumps(salary, ensure_ascii=False, separators=(",", ":")) if salary else ""
    arrangement = str(job.get("jobLocationType") or "")
    posted = str(job.get("datePosted") or "")[:10]
    return {
        "cleaned_description": description,
        "apply_url": str(job.get("url") or ""),
        "work_arrangement": arrangement,
        "salary_text": salary_text,
        "posted_date": posted if re.fullmatch(r"\d{4}-\d{2}-\d{2}", posted) else "",
    }


def oracle_detail_url(job_url: str) -> str:
    parsed = urlsplit(job_url)
    site = re.search(r"/sites/([^/]+)", parsed.path)
    job_id = re.search(r"/job/([^/?#]+)", parsed.path)
    if not parsed.hostname or not site or not job_id:
        raise ValueError("invalid Oracle Cloud job URL")
    query = urlencode({"onlyData": "true", "finder": f'ById;Id="{job_id.group(1)}",siteNumber={site.group(1)}'})
    return f"{parsed.scheme}://{parsed.netloc}/hcmRestApi/resources/latest/recruitingCEJobRequisitionDetails?{query}"


def oracle_fields(raw: str) -> dict:
    payload = json.loads(raw)
    items = payload.get("items") or []
    if not items:
        raise ValueError("Oracle detail response contained no job")
    job = items[0]
    description = clean_text(str(job.get("ExternalDescriptionStr") or ""))
    return {
        "cleaned_description": description,
        "apply_url": "",
        "work_arrangement": str(job.get("WorkplaceType") or ""),
        "salary_text": "",
        "posted_date": str(job.get("ExternalPostedStartDate") or "")[:10],
    }


def fetch(row: dict, timeout: int, retries: int) -> dict:
    result = {**row, "scraped_at": datetime.now(timezone.utc).isoformat(), "attempt_count": 0}
    for attempt in range(1, retries + 1):
        result["attempt_count"] = attempt
        try:
            fetch_url = oracle_detail_url(row["job_url"]) if row["source_type"] == "oracle_cloud" else row["job_url"]
            request = Request(fetch_url, headers={
                "User-Agent": "Mozilla/5.0 (compatible; JobPush/1.0; job-description-export)",
                "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            })
            with urlopen(request, timeout=timeout) as response:
                raw_bytes = response.read()
                charset = response.headers.get_content_charset() or "utf-8"
                raw = raw_bytes.decode(charset, errors="replace").replace("\x00", "")
                content_type = response.headers.get("Content-Type", "")
                status = getattr(response, "status", 200)
            if row["source_type"] == "oracle_cloud":
                fields = oracle_fields(raw)
            else:
                parser = JobPageParser()
                parser.feed(raw)
                fields = structured_fields(parser)
            if len(fields["cleaned_description"]) < 100:
                raise ValueError("cleaned job description shorter than 100 characters")
            return {
                **result, **fields, "raw_html": raw, "content_type": content_type,
                "http_status": status, "scrape_status": "succeeded", "scrape_error": "",
            }
        except HTTPError as exc:
            error = f"HTTP {exc.code}: {exc.reason}"
            status = exc.code
            if exc.code < 500 and exc.code not in (408, 429):
                break
        except (URLError, TimeoutError, ValueError, OSError) as exc:
            error = f"{type(exc).__name__}: {exc}"
            status = 0
        if attempt < retries:
            time.sleep(min(2 ** (attempt - 1), 4))
    return {
        **result, "raw_html": "", "cleaned_description": "", "content_type": "",
        "apply_url": "", "work_arrangement": "", "salary_text": "", "posted_date": "",
        "http_status": status, "scrape_status": "failed", "scrape_error": error,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("targets_csv")
    parser.add_argument("results_csv")
    parser.add_argument("report_json")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--retries", type=int, default=3)
    args = parser.parse_args()

    with open(args.targets_csv, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    results = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(fetch, row, args.timeout, args.retries): row for row in rows}
        for index, future in enumerate(as_completed(futures), 1):
            result = future.result()
            results.append(result)
            print(f"[{index}/{len(rows)}] {result['source_type']} {result['scrape_status']} {result['title'][:70]}", file=sys.stderr)

    columns = list(rows[0]) + [
        "raw_html", "cleaned_description", "content_type", "apply_url", "work_arrangement",
        "salary_text", "posted_date", "scraped_at", "scrape_status", "scrape_error",
        "http_status", "attempt_count",
    ] if rows else []
    with open(args.results_csv, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(results)

    by_ats = {}
    failures = {}
    for result in results:
        stats = by_ats.setdefault(result["source_type"], {"processed": 0, "succeeded": 0, "failed": 0})
        stats["processed"] += 1
        stats[result["scrape_status"]] += 1
        if result["scrape_status"] == "failed":
            reason = result["scrape_error"].split(":", 1)[0]
            failures[reason] = failures.get(reason, 0) + 1
    report = {
        "processed": len(results),
        "succeeded": sum(r["scrape_status"] == "succeeded" for r in results),
        "failed": sum(r["scrape_status"] == "failed" for r in results),
        "by_ats": by_ats,
        "failure_reasons": failures,
    }
    with open(args.report_json, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
