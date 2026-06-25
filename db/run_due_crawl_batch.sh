#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${1:-10}"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "limit must be a positive integer" >&2; exit 2; }

DUE_SITES=()
while IFS= read -r row; do
  DUE_SITES+=("$row")
done < <("${PSQL[@]}" -qAtF $'\t' -c \
  "SELECT consolidation_key, source_type, priority_tier, scope_method
   FROM jobpush.crawl_schedule_queue
   WHERE is_due
   ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
            priority_score DESC, site_id
   LIMIT $LIMIT;")

if [[ ${#DUE_SITES[@]} -eq 0 ]]; then
  echo "No verified, US-ready, supported sites are due."
  exit 0
fi

failures=0
for row in "${DUE_SITES[@]}"; do
  IFS=$'\t' read -r consolidation_key source_type priority_tier scope_method <<< "$row"
  case "$source_type" in
    apple_jobs)
      adapter_name="apple-jobs-api"; adapter_version="0.1.0"; adapter_script="scripts/crawl_apple_jobs.py" ;;
    greenhouse)
      adapter_name="greenhouse-api"; adapter_version="0.2.0"; adapter_script="scripts/crawl_greenhouse.py" ;;
    lever)
      adapter_name="lever-api"; adapter_version="0.1.0"; adapter_script="scripts/crawl_lever.py" ;;
    ashby)
      adapter_name="ashby-posting-api"; adapter_version="0.1.0"; adapter_script="scripts/crawl_ashby.py" ;;
    smartrecruiters)
      adapter_name="smartrecruiters-api"; adapter_version="0.1.0"; adapter_script="scripts/crawl_smartrecruiters.py" ;;
    workable)
      adapter_name="workable-markdown"; adapter_version="0.1.0"; adapter_script="scripts/crawl_workable.py" ;;
    jobvite)
      adapter_name="jobvite-html-jsonld"; adapter_version="0.1.0"; adapter_script="scripts/crawl_jobvite.py" ;;
    icims)
      adapter_name="icims-html"; adapter_version="0.3.0"; adapter_script="scripts/crawl_icims.py" ;;
    oracle_cloud)
      adapter_name="oracle-cloud-rest"; adapter_version="0.1.0"; adapter_script="scripts/crawl_oracle_cloud.py" ;;
    workday)
      adapter_name="workday-cxs"; adapter_version="0.1.0"; adapter_script="scripts/crawl_workday.py" ;;
    *)
      echo "Skipping unsupported source_type=$source_type" >&2
      continue ;;
  esac

  echo "==> $priority_tier $consolidation_key ($source_type)"
  if (
    export CONSOLIDATION_KEY="$consolidation_key" SOURCE_TYPE="$source_type"
    export ADAPTER_NAME="$adapter_name" ADAPTER_VERSION="$adapter_version"
    export ADAPTER_SCRIPT="$adapter_script"
    export COHORT="scheduled-$source_type" PRIORITY_TIER="$priority_tier"
    export SCOPE_METHOD="$scope_method"
    bash "$SCRIPT_DIR/lib/run_structured_adapter_pilot.sh"
  ); then
    :
  else
    failures=$((failures + 1))
  fi
done

echo "Completed ${#DUE_SITES[@]} due sites; failures=$failures"
successes=$((${#DUE_SITES[@]} - failures))
if [[ "$successes" -le 0 ]]; then
  echo "All due-site crawls failed; check adapter health before continuing." >&2
  exit 1
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Some due-site crawls failed; failures are recorded in crawl_runs and career_sites." >&2
fi
