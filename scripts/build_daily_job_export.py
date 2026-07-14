#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("export_csv")
    parser.add_argument("output_json")
    parser.add_argument("scrape_report_json")
    parser.add_argument("output_report_json")
    parser.add_argument("--discovered", type=int, required=True)
    parser.add_argument("--processed", type=int, required=True)
    parser.add_argument("--skipped", type=int, required=True)
    args = parser.parse_args()

    with open(args.export_csv, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))

    jobs = []
    for row in rows:
        jobs.append({
            "company": row["company"],
            "title": row["title"],
            "location": row["location"] or None,
            "work_arrangement": row["work_arrangement"] or None,
            "employment_type": row["employment_type"] or None,
            "salary": row["salary_text"] or None,
            "posted_date": row["posted_date"] or row["posted_text"] or None,
            "first_seen_date": row["first_seen_date"],
            "job_url": row["job_url"],
            "apply_url": row["apply_url"] or row["job_url"],
            "source": row["source_type"],
            "complete_job_description": row["cleaned_description"],
            "raw_html": row["raw_html"],
            "scrape_metadata": {
                "status": row["scrape_status"],
                "scraped_at": row["scraped_at"],
                "http_status": int(row["http_status"]) if row["http_status"] else None,
                "attempt_count": int(row["attempt_count"] or 0),
                "error": row["scrape_error"] or None,
                "content_type": row["content_type"] or None,
                "source_fingerprint": row["source_fingerprint"],
            },
        })

    Path(args.output_json).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output_json, "w", encoding="utf-8") as handle:
        json.dump(jobs, handle, ensure_ascii=False, separators=(",", ":"))

    with open(args.scrape_report_json, encoding="utf-8") as handle:
        scrape = json.load(handle)
    report = {
        "jobs_discovered": args.discovered,
        "jobs_processed": args.processed,
        "successful_jd_retrieval": scrape.get("succeeded", 0),
        "skipped_jobs": args.skipped,
        "failed_jobs": scrape.get("failed", 0),
        "exported_jobs": len(jobs),
        "success_rate_by_ats": {},
        "common_failure_reasons": scrape.get("failure_reasons", {}),
    }
    for ats, stats in scrape.get("by_ats", {}).items():
        processed = stats.get("processed", 0)
        report["success_rate_by_ats"][ats] = {
            **stats,
            "success_rate": round(stats.get("succeeded", 0) / processed, 4) if processed else None,
        }
    with open(args.output_report_json, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
