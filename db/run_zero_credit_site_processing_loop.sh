#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

MAX_CYCLES="${MAX_CYCLES:-12}"
CRAWL_BATCH_SIZE="${CRAWL_BATCH_SIZE:-300}"
GENERIC_BATCH_SIZE="${GENERIC_BATCH_SIZE:-1000}"
WAIT_SECONDS="${WAIT_SECONDS:-60}"
LOCK_FILE="/tmp/jobpush-zero-credit-site-processing.lock"

[[ "$MAX_CYCLES" =~ ^[1-9][0-9]*$ ]] || { echo "MAX_CYCLES must be positive" >&2; exit 2; }
[[ "$CRAWL_BATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || { echo "CRAWL_BATCH_SIZE must be positive" >&2; exit 2; }
[[ "$GENERIC_BATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || { echo "GENERIC_BATCH_SIZE must be positive" >&2; exit 2; }
[[ "$WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]] || { echo "WAIT_SECONDS must be positive" >&2; exit 2; }

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Another zero-credit site processing loop is already running."; exit 0; }

count_due_sites() {
  "${PSQL[@]}" -qAt -c "
    SELECT count(*)
    FROM jobpush.crawl_schedule_queue
    WHERE is_due
      AND crawl_status <> 'running';
  "
}

count_unresolved_generic_companies() {
  "${PSQL[@]}" -qAt -c "
    SELECT count(DISTINCT site.consolidation_key)
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = false
      AND COALESCE(site.last_error, '') NOT LIKE 'generic_ats_resolution_attempted%';
  "
}

for cycle in $(seq 1 "$MAX_CYCLES"); do
  echo "==> zero-credit processing cycle $cycle/$MAX_CYCLES at $(date -u +%FT%TZ)"

  if pgrep -f "run_due_crawl_batch\\.sh" >/dev/null; then
    echo "A due-crawl batch is already running; waiting ${WAIT_SECONDS}s."
    sleep "$WAIT_SECONDS"
    continue
  fi

  bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

  due_sites="$(count_due_sites)"
  unresolved_generic="$(count_unresolved_generic_companies)"
  echo "due_sites=$due_sites unresolved_generic_companies=$unresolved_generic"

  if (( due_sites > 0 )); then
    batch="$CRAWL_BATCH_SIZE"
    (( due_sites < batch )) && batch="$due_sites"
    echo "Running due crawl batch size=$batch"
    bash "$SCRIPT_DIR/run_due_crawl_batch.sh" "$batch"
    continue
  fi

  if (( unresolved_generic > 0 )); then
    batch="$GENERIC_BATCH_SIZE"
    (( unresolved_generic < batch )) && batch="$unresolved_generic"
    echo "Resolving hidden ATS from generic candidates size=$batch; Tavily credits used: 0"
    GENERIC_RESOLVE_LIMIT="$batch" GENERIC_RESOLVE_TIERS=P0,P1,P2,P3 \
      bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh"
    continue
  fi

  echo "No due sites and no unresolved generic candidates remain."
  break
done

bash "$SCRIPT_DIR/run_site_processing_status.sh"
