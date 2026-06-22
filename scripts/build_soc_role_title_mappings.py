#!/usr/bin/env python3
"""Build config/soc_role_title_mappings.csv from the workbook's 原始职位对应 sheet."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

import openpyxl

ACRONYMS = {
    "IT", "SQL", "API", "UI", "UX", "HR", "AI", "ML", "AWS", "SAP", "QA", "SDE", "H1B",
    "II", "III", "IV", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "PM", "VP", "SVP",
    "EVP", "CEO", "CFO", "CTO", "COO", "US", "UK", "NYC", "SF", "LA",
}
SMALL_WORDS = {
    "a", "an", "the", "and", "or", "of", "in", "on", "at", "to", "for", "with",
}

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "outputs/job_roles_20260621/LCA_All_Job_Roles_Summary.xlsx"
DEFAULT_OUTPUT = ROOT / "config/soc_role_title_mappings.csv"


def normalize_soc_code(raw_code: str) -> str:
    match = re.match(r"^\s*(\d{2})-(\d{4})(?:\.(\d{1,2}))?", str(raw_code).strip())
    if not match:
        return ""
    extension = match.group(3) or "00"
    return f"{match.group(1)}{match.group(2)}{extension.zfill(2)}"


def normalize_display_title(raw: str) -> str:
    raw = " ".join(str(raw).split())
    if not raw:
        return raw

    letters = [char for char in raw if char.isalpha()]
    if not letters or sum(char.isupper() for char in letters) / len(letters) <= 0.9:
        return raw

    words = raw.split()
    normalized: list[str] = []
    for index, word in enumerate(words):
        punctuation = ""
        core = word
        while core and not core[-1].isalnum():
            punctuation = core[-1] + punctuation
            core = core[:-1]
        while core and not core[0].isalnum():
            punctuation = core[0] + punctuation
            core = core[1:]

        upper = core.upper()
        if upper in ACRONYMS or re.fullmatch(r"[IVX]+", upper):
            normalized.append(upper + punctuation)
        elif index > 0 and core.lower() in SMALL_WORDS:
            normalized.append(core.lower() + punctuation)
        else:
            normalized.append(core.capitalize() + punctuation)
    return " ".join(normalized)


def parse_count(value: object) -> int:
    if value is None:
        return 0
    return int(str(value).replace(",", "").strip() or 0)


def build_rows(input_path: Path) -> list[dict[str, object]]:
    workbook = openpyxl.load_workbook(input_path, read_only=True, data_only=True)
    worksheet = workbook["原始职位对应"]

    grouped: dict[tuple[str, str], dict[str, object]] = {}
    for index, row in enumerate(worksheet.iter_rows(values_only=True)):
        if index < 4 or not row or not row[0]:
            continue

        raw_job_title = str(row[0]).strip()
        normalized_soc_code = normalize_soc_code(row[1])
        if not raw_job_title or not normalized_soc_code:
            continue

        candidate = {
            "raw_job_title": raw_job_title,
            "normalized_soc_code": normalized_soc_code,
            "soc_title": normalize_display_title(str(row[2]).strip()),
            "soc_lca_count": parse_count(row[3]),
            "raw_lca_count": parse_count(row[4]),
            "normalized_job_title": normalize_display_title(raw_job_title),
        }
        key = (raw_job_title, normalized_soc_code)
        current = grouped.get(key)
        if current is None or candidate["raw_lca_count"] > current["raw_lca_count"]:
            grouped[key] = candidate

    workbook.close()
    return sorted(
        grouped.values(),
        key=lambda item: (-int(item["raw_lca_count"]), str(item["raw_job_title"])),
    )


def main() -> int:
    input_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_INPUT
    output_path = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_OUTPUT

    if not input_path.exists():
        print(f"Input workbook not found: {input_path}", file=sys.stderr)
        return 1

    rows = build_rows(input_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "raw_job_title",
                "normalized_soc_code",
                "soc_title",
                "soc_lca_count",
                "raw_lca_count",
                "normalized_job_title",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
