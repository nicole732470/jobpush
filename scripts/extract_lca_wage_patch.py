#!/usr/bin/env python3
"""Stream official DOL LCA wage fields from a large XLSX into a compact CSV."""

import argparse
import csv
import re
import xml.etree.ElementTree as ET
import zipfile


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
WANTED_COLUMNS = [
    "CASE_NUMBER",
    "WAGE_RATE_OF_PAY_FROM",
    "WAGE_RATE_OF_PAY_TO",
    "WAGE_UNIT_OF_PAY",
    "PREVAILING_WAGE",
    "PW_UNIT_OF_PAY",
    "PW_TRACKING_NUMBER",
    "PW_WAGE_LEVEL",
    "PW_OES_YEAR",
    "PW_OTHER_SOURCE",
    "PW_OTHER_YEAR",
    "PW_SURVEY_PUBLISHER",
    "PW_SURVEY_NAME",
]


def column_index(cell_ref):
    letters = re.match(r"[A-Z]+", cell_ref).group(0)
    result = 0
    for char in letters:
        result = result * 26 + ord(char) - 64
    return result - 1


def load_shared_strings(archive):
    if "xl/sharedStrings.xml" not in archive.namelist():
        return []
    values = []
    with archive.open("xl/sharedStrings.xml") as source:
        for _, element in ET.iterparse(source, events=("end",)):
            if element.tag == f"{{{MAIN_NS}}}si":
                values.append("".join(node.text or "" for node in element.iter(f"{{{MAIN_NS}}}t")))
                element.clear()
    return values


def first_sheet_path(archive):
    workbook = ET.parse(archive.open("xl/workbook.xml")).getroot()
    first_sheet = workbook.find(f".//{{{MAIN_NS}}}sheet")
    relationship_id = first_sheet.attrib[f"{{{REL_NS}}}id"]
    relationships = ET.parse(archive.open("xl/_rels/workbook.xml.rels")).getroot()
    for relationship in relationships.findall(f"{{{PKG_REL_NS}}}Relationship"):
        if relationship.attrib["Id"] == relationship_id:
            target = relationship.attrib["Target"].lstrip("/")
            return target if target.startswith("xl/") else f"xl/{target}"
    raise RuntimeError("Unable to resolve the first worksheet")


def cell_value(cell, strings):
    cell_type = cell.attrib.get("t")
    if cell_type == "inlineStr":
        return "".join(node.text or "" for node in cell.iter(f"{{{MAIN_NS}}}t"))
    value = cell.find(f"{{{MAIN_NS}}}v")
    if value is None or value.text is None:
        return ""
    return strings[int(value.text)] if cell_type == "s" else value.text


def iter_rows(archive, sheet_path, strings):
    with archive.open(sheet_path) as source:
        for _, element in ET.iterparse(source, events=("end",)):
            if element.tag == f"{{{MAIN_NS}}}row":
                yield {
                    column_index(cell.attrib["r"]): cell_value(cell, strings)
                    for cell in element.findall(f"{{{MAIN_NS}}}c")
                }
                element.clear()


def normalize_header(value):
    return re.sub(r"[^A-Z0-9]+", "_", value.strip().upper()).strip("_")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook")
    parser.add_argument("output_csv")
    args = parser.parse_args()

    with zipfile.ZipFile(args.workbook) as archive:
        strings = load_shared_strings(archive)
        rows = iter_rows(archive, first_sheet_path(archive), strings)
        header_row = next(rows)
        headers = {normalize_header(value): index for index, value in header_row.items()}
        missing = [column for column in WANTED_COLUMNS if column not in headers]
        if missing:
            raise RuntimeError(f"Missing expected columns: {missing}")

        with open(args.output_csv, "w", newline="", encoding="utf-8") as output:
            writer = csv.writer(output)
            writer.writerow([column.lower() for column in WANTED_COLUMNS])
            count = 0
            for row in rows:
                values = [row.get(headers[column], "") for column in WANTED_COLUMNS]
                if values[0]:
                    writer.writerow(values)
                    count += 1

    print(f"Extracted {count:,} official LCA wage rows")


if __name__ == "__main__":
    main()
