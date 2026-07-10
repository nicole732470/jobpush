#!/usr/bin/env bash
# Multi-round zero-credit generic HTML hidden-ATS resolver.
# Fetches structured ATS links from corporate career pages, then auto-trusts findings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GENERIC_RESOLVE_ROUNDS="${GENERIC_RESOLVE_ROUNDS:-8}"
GENERIC_RESOLVE_LIMIT="${GENERIC_RESOLVE_LIMIT:-1500}"
GENERIC_RESOLVE_TIERS="${GENERIC_RESOLVE_TIERS:-P2,P3}"
GENERIC_RESOLVE_RETRY="${GENERIC_RESOLVE_RETRY:-1}"

echo "=== Generic resolver wave: tiers=$GENERIC_RESOLVE_TIERS limit=$GENERIC_RESOLVE_LIMIT rounds=$GENERIC_RESOLVE_ROUNDS retry=$GENERIC_RESOLVE_RETRY ==="
bash "$SCRIPT_DIR/run_p2_p3_review_backlog.sh"

echo "=== Pre-wave auto-trust ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

completed_rounds=0
for round in $(seq 1 "$GENERIC_RESOLVE_ROUNDS"); do
  echo "=== Round $round/$GENERIC_RESOLVE_ROUNDS: generic HTML hidden-ATS resolver ==="
  round_output="$(
    GENERIC_RESOLVE_LIMIT="$GENERIC_RESOLVE_LIMIT" \
      GENERIC_RESOLVE_TIERS="$GENERIC_RESOLVE_TIERS" \
      GENERIC_RESOLVE_RETRY="$GENERIC_RESOLVE_RETRY" \
      bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh" 2>&1
  )" || {
    echo "$round_output"
    exit 1
  }
  echo "$round_output"

  if echo "$round_output" | grep -q "No generic HTML candidates require ATS-link resolution."; then
    echo "Generic resolver backlog exhausted after $completed_rounds full round(s)."
    break
  fi

  completed_rounds=$round
  echo "=== Round $round auto-trust ==="
  bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"
done

echo "=== Final auto-trust ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== After: backlog ($completed_rounds resolver round(s) completed) ==="
bash "$SCRIPT_DIR/run_p2_p3_review_backlog.sh"
