#!/usr/bin/env bash
# P2 ops continuation: fix failures, crawl due sites, zero-credit expand (no Tavily).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "=== P2 snapshot (before) ==="
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/analysis/p2_failed_crawl_distribution.sql"

echo "=== Step 1: reject obvious bad failed URLs (P0-P2) ==="
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/ops/reject_obvious_bad_failed_sites.sql" || true

echo "=== Step 2: resolve transient failures + demote stale 404 URLs ==="
bash "$SCRIPT_DIR/run_resolve_current_failed_sites.sh"

echo "=== Step 3: quarantine chronic P2 failures (iCIMS/generic timeout, Workday payload, GH 404) ==="
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/ops/quarantine_p2_chronic_failures.sql"

echo "=== Step 4: auto-trust ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

P2_DUE=$("${PSQL[@]}" -Atc \
  "SELECT count(*) FROM jobpush.crawl_schedule_queue
   WHERE priority_tier='P2' AND is_due AND crawl_status <> 'running';")
echo "=== Step 5: P2 due crawl (count=$P2_DUE) ==="
if [[ "$P2_DUE" -gt 0 ]]; then
  LIMIT="${P2_DUE_LIMIT:-$P2_DUE}"
  PRIORITY_TIER_FILTER=P2 SKIP_POST_CRAWL_TITLE_ML=1 \
    bash "$SCRIPT_DIR/run_due_crawl_batch.sh" "$LIMIT"
fi

echo "=== Step 6: P2 structured source wave (greenhouse/icims/workday) ==="
PRIORITY_TIER_FILTER=P2 SKIP_POST_CRAWL_TITLE_ML=1 \
  bash "$SCRIPT_DIR/run_due_crawl_p2_structured_wave.sh"

echo "=== Step 7: zero-credit ATS guess P2+P3 ==="
ATS_GUESS_TIERS=P2,P3 ATS_GUESS_LIMIT="${ATS_GUESS_LIMIT:-1000}" \
  bash "$SCRIPT_DIR/run_guess_ats_sites.sh"

echo "=== Step 8: auto-trust after guess ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Step 9: zero-credit generic HTML resolver P2 ==="
GENERIC_RESOLVE_TIERS=P2 GENERIC_RESOLVE_LIMIT="${GENERIC_RESOLVE_LIMIT:-2000}" \
  bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh"

echo "=== Step 10: final auto-trust ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== P2 snapshot (after) ==="
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/analysis/p2_failed_crawl_distribution.sql"
bash "$SCRIPT_DIR/run_p2_crawl_blockers.sh"
