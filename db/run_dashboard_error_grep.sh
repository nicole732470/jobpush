#!/usr/bin/env bash
set -euo pipefail

SINCE="${1:-2026-06-27 16:39:44 UTC}"

journalctl -u jobpush-dashboard.service --since "$SINCE" --no-pager \
  | grep -Ei 'Traceback|Uncaught|ERROR|UndefinedColumn|IndexError' || true
