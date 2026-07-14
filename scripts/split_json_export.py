#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_list", type=Path)
    parser.add_argument("--max-bytes", type=int, default=16_000_000)
    args = parser.parse_args()
    jobs = json.loads(args.source.read_text(encoding="utf-8"))
    chunks, chunk, size = [], [], 2
    for job in jobs:
        encoded = json.dumps(job, ensure_ascii=False, separators=(",", ":")).encode()
        if chunk and size + len(encoded) + 1 > args.max_bytes:
            chunks.append(chunk)
            chunk, size = [], 2
        chunk.append(job)
        size += len(encoded) + 1
    if chunk or not chunks:
        chunks.append(chunk)
    paths = []
    for index, jobs_chunk in enumerate(chunks, 1):
        path = args.source.with_name(f"{args.source.stem}.part-{index}-of-{len(chunks)}.json")
        path.write_text(json.dumps(jobs_chunk, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        paths.append(str(path))
    args.output_list.write_text("\n".join(paths) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
