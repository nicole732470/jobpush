#!/usr/bin/env python3
"""Copy a row slice from one CSV to another without breaking multiline fields."""

import argparse
import csv


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--offset", type=int, required=True)
    parser.add_argument("--limit", type=int, required=True)
    args = parser.parse_args()

    with open(args.source, newline="", encoding="utf-8") as source:
        reader = csv.DictReader(source)
        fieldnames = reader.fieldnames or []
        rows = []
        for index, row in enumerate(reader):
            if index < args.offset:
                continue
            if len(rows) >= args.limit:
                break
            rows.append(row)

    with open(args.destination, "w", newline="", encoding="utf-8") as destination:
        writer = csv.DictWriter(destination, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
