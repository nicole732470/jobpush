#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _ in $(seq 1 20); do
  output="$(GENERIC_JSONLD_TIERS=P3 GENERIC_JSONLD_LIMIT=1000 GENERIC_JSONLD_WORKERS=40 bash "$SCRIPT_DIR/run_promote_generic_jsonld_sites_1000.sh")"
  echo "$output"
  grep -q 'No generic HTML candidates require JSON-LD probing.' <<< "$output" && break
done
