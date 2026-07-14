#!/usr/bin/env bash
# Continuously turn unresolved companies into crawlable career sites.
# MODE=daily uses no paid search credits. MODE=monthly first drains the
# configured Tavily keys, then runs the same deterministic processing stages.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

MODE="${MODE:-daily}"
ATS_GUESS_LIMIT="${ATS_GUESS_LIMIT:-250}"
GENERIC_RESOLVE_LIMIT="${GENERIC_RESOLVE_LIMIT:-500}"
LOCK_FILE="${LOCK_FILE:-/tmp/jobpush-site-growth.lock}"

[[ "$MODE" == "daily" || "$MODE" == "monthly" ]] || {
  echo "MODE must be daily or monthly" >&2
  exit 2
}

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Another site-growth workflow is already running; exiting cleanly."; exit 0; }

snapshot() {
  local label="$1"
  echo "=== Site-growth snapshot: $label ==="
  "${PSQL[@]}" -qAtF $'\t' -c "
    SELECT
      count(DISTINCT target.consolidation_key) FILTER (WHERE target.enabled) AS enabled_companies,
      count(DISTINCT site.consolidation_key) FILTER (
        WHERE site.verification_status='verified' AND site.crawl_enabled
      ) AS crawlable_companies,
      count(DISTINCT target.consolidation_key) FILTER (
        WHERE target.enabled AND target.discovery_status='review_pending'
      ) AS review_pending_companies
    FROM jobpush.crawl_targets target
    LEFT JOIN jobpush.career_sites site USING (consolidation_key);
  " | awk -F '\t' '{printf "enabled_companies=%s crawlable_companies=%s review_pending_companies=%s\n", $1, $2, $3}'
}

echo "=== Site-growth workflow started mode=$MODE at $(date -u +%FT%TZ) ==="
snapshot before

if [[ "$MODE" == "monthly" ]]; then
  echo "=== Stage 1/5: discover never-searched companies with every configured Tavily key ==="
  bash "$SCRIPT_DIR/deplete_tavily_keys_from_secret.sh"
else
  echo "=== Stage 1/5: paid discovery skipped in daily zero-credit mode ==="
fi

echo "=== Stage 2/5: auto-enable safe structured ATS candidates ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "=== Stage 3/5: deterministically guess structured ATS boards (zero credits) ==="
ATS_GUESS_TIERS=P0,P1,P2,P3 ATS_GUESS_LIMIT="$ATS_GUESS_LIMIT" \
  bash "$SCRIPT_DIR/run_guess_ats_sites.sh"

echo "=== Stage 4/5: resolve ATS links from retained career pages (zero credits) ==="
GENERIC_RESOLVE_TIERS=P0,P1,P2,P3 GENERIC_RESOLVE_LIMIT="$GENERIC_RESOLVE_LIMIT" \
  bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh"

echo "=== Stage 5/5: auto-enable newly resolved supported sites ==="
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

snapshot after
echo "=== Site-growth workflow completed mode=$MODE at $(date -u +%FT%TZ) ==="
echo "Newly enabled sites are now due and will be ingested by the next nightly crawl."
