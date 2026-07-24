#!/usr/bin/env python3
"""Keep only daily-export links that are still publicly reachable."""
import argparse
import json
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ERROR_URL = re.compile(r"(?:[?&](?:error|errortype)=|/(?:404|errorpage)(?:/|$))", re.I)


def rejection_reason(status: int, final_url: str) -> str:
    if status in (400, 404, 410) or status >= 500:
        return f"http_{status}"
    if ERROR_URL.search(final_url):
        return "error_redirect"
    return ""


def check(index: int, job: dict, timeout: int) -> tuple[int, dict, str]:
    url = job.get("apply_url") or job.get("job_url") or ""
    if not url.startswith(("https://", "http://")):
        return index, job, "missing_url"
    try:
        request = Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; JobPush/1.0)"})
        with urlopen(request, timeout=timeout) as response:
            reason = rejection_reason(getattr(response, "status", 200), response.geturl())
    except HTTPError as exc:
        # 401/403 are often bot protection: do not treat them as a closed job.
        reason = "" if exc.code in (401, 403) else rejection_reason(exc.code, exc.geturl() or url)
    except (URLError, TimeoutError, OSError):
        reason = ""  # A transient network failure must not discard a valid job.
    if not reason:
        job["job_url"] = url
    return index, job, reason


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_jsonl")
    parser.add_argument("output_jsonl")
    parser.add_argument("report_json")
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--timeout", type=int, default=15)
    args = parser.parse_args()
    with open(args.input_jsonl, encoding="utf-8") as handle:
        jobs = [json.loads(line) for line in handle if line.strip()]
    results = [None] * len(jobs)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(check, i, job, args.timeout) for i, job in enumerate(jobs)]
        for future in as_completed(futures):
            index, job, reason = future.result()
            results[index] = (job, reason)
    kept = [job for job, reason in results if not reason]
    rejected = [reason for _, reason in results if reason]
    with open(args.output_jsonl, "w", encoding="utf-8") as handle:
        for job in kept:
            handle.write(json.dumps(job, ensure_ascii=False) + "\n")
    with open(args.report_json, "w", encoding="utf-8") as handle:
        json.dump({"checked": len(jobs), "kept": len(kept), "rejected": len(rejected),
                   "reasons": {reason: rejected.count(reason) for reason in sorted(set(rejected))}}, handle)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
