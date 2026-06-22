#!/usr/bin/env python3
"""Build LinkedIn 2026 top employer lists and match terms from the workbook."""

from __future__ import annotations

import csv
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = Path.home() / "Downloads/linkedin_top_companies_2026_us_europe.xlsx"
EMPLOYERS_CSV = ROOT / "config/linkedin_top_employers_2026.csv"
MATCH_TERMS_CSV = ROOT / "config/linkedin_top_employer_match_terms.csv"

# Extra search keys for brand abbreviations and legal-name variants.
EXTRA_MATCH_KEYS: dict[str, list[tuple[str, str]]] = {
  # linkedin_name: [(match_key, match_kind)]
    "EY": [("ernst-and-young", "prefix"), ("ernst-young", "prefix")],
    "PwC": [("pwc", "prefix"), ("pricewaterhouse", "prefix")],
    "JPMorganChase": [("jpmorgan", "prefix"), ("jp-morgan", "prefix")],
    "AT&T": [("att", "prefix"), ("at-and-t", "prefix")],
    "Citi": [("citigroup", "prefix"), ("citibank", "prefix")],
    "Procter & Gamble": [("procter-gamble", "prefix"), ("procter-and-gamble", "prefix")],
    "GE HealthCare": [("ge-healthcare", "prefix"), ("ge-health", "prefix")],
    "HCA Healthcare": [("hca-healthcare", "prefix"), ("hca", "prefix")],
    "Johnson & Johnson": [("johnson-and-johnson", "prefix"), ("johnson-johnson", "prefix")],
    "Merck": [("merck", "prefix")],
    "Meta": [("meta-platforms", "prefix"), ("facebook", "prefix")],
    "Alphabet/Google": [("alphabet", "prefix"), ("google", "prefix")],
    "Salesforce": [("salesforce", "prefix")],
    "ServiceNow": [("servicenow", "prefix")],
    "Uber": [("uber", "prefix")],
    "NVIDIA": [("nvidia", "prefix")],
    "Intel": [("intel", "prefix")],
    "Cisco": [("cisco", "prefix")],
    "Oracle": [("oracle", "prefix")],
    "Adobe": [("adobe", "prefix")],
    "Siemens": [("siemens", "prefix")],
    "SAP": [("sap", "prefix")],
    "Accenture": [("accenture", "prefix")],
    "Deloitte": [("deloitte", "prefix")],
    "KPMG": [("kpmg", "prefix")],
    "McKinsey & Company": [("mckinsey", "prefix")],
    "Boston Consulting Group (BCG)": [("boston-consulting", "prefix"), ("bcg", "exact")],
    "Bain & Company": [("bain-and-company", "prefix"), ("bain", "prefix")],
}


def slugify(text: str) -> str:
    text = unicodedata.normalize("NFKD", text)
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = text.lower()
    text = text.replace("&", " and ")
    text = re.sub(r"[^a-z0-9\s-]", " ", text)
    text = re.sub(r"\s+", "-", text.strip())
    text = re.sub(r"-+", "-", text)
    return text.strip("-")


def split_brand_names(linkedin_name: str) -> list[str]:
    names: list[str] = []
    for chunk in re.split(r"/", linkedin_name):
        chunk = chunk.strip()
        if not chunk:
            continue
        chunk = re.sub(r"\s*\([^)]*\)\s*$", "", chunk).strip()
        names.append(chunk)
    return names or [linkedin_name]


def choose_match_kind(match_key: str) -> str:
    if len(match_key) <= 3:
        return "exact"
    return "prefix"


def build_match_terms(linkedin_name: str) -> list[tuple[str, str, str]]:
    """Return (match_key, match_kind, term_source)."""
    terms: dict[tuple[str, str], str] = {}

    def add_term(raw_name: str, source: str) -> None:
        key = slugify(raw_name)
        if not key:
            return
        kind = choose_match_kind(key)
        terms.setdefault((key, kind), source)

        # Also add without common legal suffix words for multi-token names.
        stripped = re.sub(
            r"-(inc|llc|ltd|corp|corporation|company|co|plc|gmbh|sa|ag|group)$",
            "",
            key,
        )
        if stripped and stripped != key:
            terms.setdefault((stripped, choose_match_kind(stripped)), f"{source}:stripped")

    for brand in split_brand_names(linkedin_name):
        add_term(brand, "brand")
        add_term(linkedin_name, "linkedin_name")

    for match_key, match_kind in EXTRA_MATCH_KEYS.get(linkedin_name, []):
        terms.setdefault((match_key, match_kind), "manual_alias")

    return [
        (match_key, match_kind, source)
        for (match_key, match_kind), source in sorted(terms.items())
    ]


def build_rows(input_path: Path) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    workbook = openpyxl.load_workbook(input_path, read_only=True, data_only=True)
    sheet = workbook["LinkedIn 2026 Lists"]

    appearances: dict[str, dict[str, object]] = {}
    region_sets: dict[str, set[str]] = defaultdict(set)
    rank_best: dict[str, int] = {}

    for row in sheet.iter_rows(min_row=2, values_only=True):
        region, rank, company, source_url = row
        if not company:
            continue
        company = str(company).strip()
        region = str(region).strip()
        rank = int(rank)
        region_sets[company].add(region)
        rank_best[company] = min(rank_best.get(company, rank), rank)
        if company not in appearances:
            appearances[company] = {
                "employer_key": slugify(company),
                "linkedin_name": company,
                "best_rank": rank,
                "appearance_count": 1,
                "source_url": str(source_url).strip() if source_url else "",
            }
        else:
            appearances[company]["appearance_count"] += 1
            appearances[company]["best_rank"] = min(
                int(appearances[company]["best_rank"]), rank
            )

    employer_rows: list[dict[str, object]] = []
    match_rows: list[dict[str, object]] = []

    for company, data in sorted(
        appearances.items(), key=lambda item: (int(item[1]["best_rank"]), item[0])
    ):
        employer_key = str(data["employer_key"])
        employer_rows.append(
            {
                "employer_key": employer_key,
                "linkedin_name": company,
                "best_rank": data["best_rank"],
                "appearance_count": data["appearance_count"],
                "regions": "; ".join(sorted(region_sets[company])),
                "source_url": data["source_url"],
                "source_year": 2026,
                "notes": "LinkedIn Top Companies 2026 (US + Europe lists, deduplicated)",
            }
        )
        for match_key, match_kind, term_source in build_match_terms(company):
            match_rows.append(
                {
                    "employer_key": employer_key,
                    "linkedin_name": company,
                    "match_key": match_key,
                    "match_kind": match_kind,
                    "term_source": term_source,
                }
            )

    return employer_rows, match_rows


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main(argv: list[str]) -> int:
    input_path = Path(argv[1]) if len(argv) > 1 else DEFAULT_INPUT
    if not input_path.exists():
        print(f"Input workbook not found: {input_path}", file=sys.stderr)
        return 1

    employer_rows, match_rows = build_rows(input_path)
    write_csv(
        EMPLOYERS_CSV,
        employer_rows,
        [
            "employer_key",
            "linkedin_name",
            "best_rank",
            "appearance_count",
            "regions",
            "source_url",
            "source_year",
            "notes",
        ],
    )
    write_csv(
        MATCH_TERMS_CSV,
        match_rows,
        ["employer_key", "linkedin_name", "match_key", "match_kind", "term_source"],
    )

    print(f"Wrote {len(employer_rows)} employers -> {EMPLOYERS_CSV}")
    print(f"Wrote {len(match_rows)} match terms -> {MATCH_TERMS_CSV}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
