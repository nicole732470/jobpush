#!/usr/bin/env python3
"""Classify unresolved JobPush titles with an OpenAI-compatible chat API.

The script is intentionally auditable: it writes SQL inserts only. A DB function
then applies high-confidence decisions while preserving manual labels.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen

PROMPT_VERSION = "jobpush-title-ai-v2"
PROFILE_VERSION_DEFAULT = "2026-06-27-draft-5"

SYSTEM_PROMPT = """You classify US career-site job titles for Nicole's job search.

Return strict JSON only. No markdown.

Goal: recommend only jobs Nicole should plausibly apply to. Human review is for rare ambiguous cases, not for obvious no/yes decisions.

Target tracks:
- Product / technical product / product owner / product analyst / product marketing.
- Solutions engineer / solution architect / systems engineer when software/product/customer implementation oriented.
- Applied AI / LLM application / AI developer / forward deployed engineer / agentic AI builder.
- Customer success / technical account roles.
- Non-senior software, full-stack, backend, frontend, DevOps, cloud, data engineering, QA/test, cybersecurity.
- Data analyst, business analyst, BI analyst/engineer, consultant, marketing analyst/specialist.

Avoid / non-target:
- Too senior: senior, sr, lead, staff, principal, director, executive director, VP, head, chief, distinguished, fellow.
- All Senior/Sr roles are non_target, even if the base role family is otherwise target: Senior Product Manager, Senior Software Engineer, Sr Backend Engineer, Senior Data Engineer, Sr Customer Success Manager, etc.
- ML model development/research, applied scientist, research scientist/engineer.
- Mechanical, electrical, CAD/EDA, embedded, firmware, RF, antenna, circuit, ASIC, RTL, semiconductor, chip, CPU/GPU/SoC, hardware roles.
- HR, recruiter, talent acquisition, people operations.
- Accounting, tax, audit, payroll, bookkeeping.
- Warehouse, retail, in-store, cashier, merchandiser, Xfinity/store/front-line sales, call center/customer service rep.
- Manufacturing/factory/plant/operator/assembler/technician/production floor roles.
- Required non-English/non-Chinese language roles and obvious non-US titles. Chinese/Mandarin requirements are allowed.

Seniority nuance:
- Senior/Sr is always a hard avoid signal for the current search.
- Manager is not automatically senior if it means Product Manager, Program Manager, Account Manager, Customer Success Manager, etc.
- If a title has both a target family and a hard avoid/seniority/domain signal, choose non_target.

Output schema:
{"results":[{"normalized_title":"...","classification_status":"target|non_target|review","canonical_role":"short role family or null","confidence":0.0-1.0,"rationale":"brief reason"}]}

Use review only when the title genuinely cannot be resolved from title + context.
"""


def api_url(base_url: str) -> str:
    base = base_url.rstrip("/") + "/"
    if base.endswith("/chat/completions/"):
        return base.rstrip("/")
    return urljoin(base, "chat/completions")


def normalize_status(value: Any) -> str:
    value = str(value or "").strip().lower()
    if value in {"target", "non_target", "review"}:
        return value
    if value in {"non-target", "nontarget", "no", "skip"}:
        return "non_target"
    if value in {"yes", "apply"}:
        return "target"
    return "review"


def clamp_confidence(value: Any) -> float:
    try:
        confidence = float(value)
    except Exception:
        return 0.0
    return max(0.0, min(1.0, confidence))


def sql_literal(value: Any) -> str:
    if value is None:
        return "NULL"
    text = str(value)
    return "'" + text.replace("'", "''") + "'"


def call_model(base_url: str, api_key: str, model: str, rows: list[dict[str, str]], timeout: int) -> dict[str, Any]:
    payload = {
        "model": model,
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": json.dumps({"titles": rows}, ensure_ascii=False)},
        ],
    }
    def _post(payload_dict: dict[str, Any]) -> str:
        data = json.dumps(payload_dict).encode("utf-8")
        req = Request(
            api_url(base_url),
            data=data,
            method="POST",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        with urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8")

    try:
        raw = _post(payload)
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:1000]
        if "response_format" not in detail.lower() and exc.code not in {400, 422}:
            raise RuntimeError(f"LLM HTTP {exc.code}: {detail}") from exc
        fallback = dict(payload)
        fallback.pop("response_format", None)
        try:
            raw = _post(fallback)
        except HTTPError as fallback_exc:
            fallback_detail = fallback_exc.read().decode("utf-8", errors="replace")[:1000]
            raise RuntimeError(f"LLM HTTP {fallback_exc.code}: {fallback_detail}") from fallback_exc
    except URLError as exc:
        raise RuntimeError(f"LLM URL error: {exc}") from exc

    outer = json.loads(raw)
    content = outer["choices"][0]["message"].get("content") or ""
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        match = re.search(r"\{[\s\S]*\}", content)
        if not match:
            raise
        return json.loads(match.group(0))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-sql", required=True, type=Path)
    parser.add_argument("--limit", type=int, default=300)
    parser.add_argument("--batch-size", type=int, default=20)
    parser.add_argument("--sleep", type=float, default=0.2)
    parser.add_argument("--profile-version", default=os.environ.get("JOBPUSH_PROFILE_VERSION", PROFILE_VERSION_DEFAULT))
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()

    api_key = os.environ.get("LLM_API_KEY") or os.environ.get("OPENAI_API_KEY") or os.environ.get("OPENROUTER_API_KEY")
    base_url = os.environ.get("LLM_BASE_URL", "https://api.openai.com/v1")
    model = os.environ.get("LLM_MODEL", "gpt-4.1-mini")
    if not api_key:
        raise SystemExit("LLM_API_KEY/OPENAI_API_KEY is required")

    with args.input.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)[: args.limit]

    inserts: list[str] = ["BEGIN;"]
    total = 0
    for start in range(0, len(rows), args.batch_size):
        chunk = rows[start : start + args.batch_size]
        model_rows = [
            {
                "normalized_title": row.get("normalized_title", ""),
                "example_title": row.get("example_title", ""),
                "active_posting_count": row.get("active_posting_count", ""),
                "company_count": row.get("company_count", ""),
                "example_companies": row.get("example_companies", ""),
                "soc_titles": row.get("matched_soc_titles", ""),
                "suggestion_reason": row.get("suggestion_reason", ""),
            }
            for row in chunk
        ]
        input_text = json.dumps(model_rows, sort_keys=True, ensure_ascii=False)
        input_hash = hashlib.sha256(input_text.encode("utf-8")).hexdigest()
        try:
            response = call_model(base_url, api_key, model, model_rows, args.timeout)
        except Exception as exc:  # noqa: BLE001 - keep the batch moving; audit rows record review fallback.
            print(f"chunk failed ({exc}); retrying one title at a time", file=sys.stderr)
            single_results: list[dict[str, Any]] = []
            for single in model_rows:
                try:
                    single_response = call_model(base_url, api_key, model, [single], args.timeout)
                    single_items = single_response.get("results") or []
                    if isinstance(single_items, list) and single_items:
                        single_results.append(single_items[0])
                    else:
                        raise RuntimeError("single-title response missing results")
                except Exception as single_exc:  # noqa: BLE001
                    single_results.append({
                        "normalized_title": single["normalized_title"],
                        "classification_status": "review",
                        "canonical_role": None,
                        "confidence": 0,
                        "rationale": f"AI parse/call failed: {single_exc}",
                    })
            response = {"results": single_results}
        results = response.get("results") or []
        if not isinstance(results, list):
            raise RuntimeError("Model response missing results list")
        by_title = {str(item.get("normalized_title", "")).strip().casefold(): item for item in results if isinstance(item, dict)}
        for row in model_rows:
            key = row["normalized_title"].strip().casefold()
            item = by_title.get(key)
            if not item:
                item = {
                    "normalized_title": row["normalized_title"],
                    "classification_status": "review",
                    "canonical_role": None,
                    "confidence": 0,
                    "rationale": "model omitted this title",
                }
            status = normalize_status(item.get("classification_status"))
            confidence = clamp_confidence(item.get("confidence"))
            canonical_role = item.get("canonical_role") or None
            rationale = (str(item.get("rationale") or "")[:1000]).strip()
            raw = json.dumps(item, ensure_ascii=False, sort_keys=True)
            inserts.append(
                "INSERT INTO jobpush.job_title_ai_classifications "
                "(normalized_title, classification_status, canonical_role, confidence, model_name, prompt_version, profile_version, input_hash, rationale, raw_response) VALUES ("
                + ", ".join([
                    sql_literal(row["normalized_title"]),
                    sql_literal(status),
                    sql_literal(canonical_role),
                    f"{confidence:.4f}",
                    sql_literal(model),
                    sql_literal(PROMPT_VERSION),
                    sql_literal(args.profile_version),
                    sql_literal(input_hash),
                    sql_literal(rationale),
                    sql_literal(raw) + "::jsonb",
                ])
                + ") ON CONFLICT (normalized_title, prompt_version, profile_version, model_name, input_hash) DO NOTHING;"
            )
            total += 1
        print(f"classified {min(start + len(chunk), len(rows))}/{len(rows)}", file=sys.stderr)
        if args.sleep:
            time.sleep(args.sleep)
    inserts.append("COMMIT;")
    args.output_sql.write_text("\n".join(inserts) + "\n", encoding="utf-8")
    print(json.dumps({"titles": total, "output_sql": str(args.output_sql)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
