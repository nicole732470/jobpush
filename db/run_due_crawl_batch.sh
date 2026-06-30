#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${1:-10}"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "limit must be a positive integer" >&2; exit 2; }
SITE_ID_FILTER="${SITE_ID_FILTER:-}"
if [[ -n "$SITE_ID_FILTER" ]]; then
  [[ "$SITE_ID_FILTER" =~ ^[1-9][0-9]*$ ]] || { echo "SITE_ID_FILTER must be a positive integer" >&2; exit 2; }
  SITE_ID_WHERE="AND site_id=$SITE_ID_FILTER"
else
  SITE_ID_WHERE=""
fi

DUE_SITES=()
while IFS= read -r row; do
  DUE_SITES+=("$row")
done < <("${PSQL[@]}" -qAtF $'\t' -c \
  "SELECT consolidation_key, source_type, priority_tier, scope_method, site_id
   FROM jobpush.crawl_schedule_queue
   WHERE is_due
     AND crawl_status <> 'running'
     $SITE_ID_WHERE
   ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
            priority_score DESC, site_id
   LIMIT $LIMIT;")

if [[ ${#DUE_SITES[@]} -eq 0 ]]; then
  echo "No verified, US-ready, supported sites are due."
  exit 0
fi

failures=0
for row in "${DUE_SITES[@]}"; do
  IFS=$'\t' read -r consolidation_key source_type priority_tier scope_method site_id <<< "$row"
  case "$source_type" in
    apple_jobs)
      adapter_name="apple-jobs-api"; adapter_version="0.1.0"; adapter_script="scripts/crawl_apple_jobs.py" ;;
    amazon_jobs)
      adapter_name="amazon-jobs-json"; adapter_version="0.1.0"; adapter_script="scripts/crawl_amazon_jobs.py" ;;
    google_jobs)
      adapter_name="google-careers-html"; adapter_version="0.1.0"; adapter_script="scripts/crawl_google_jobs.py" ;;
    cognizant_jobs)
      adapter_name="cognizant-careers-html"; adapter_version="0.1.0"; adapter_script="scripts/crawl_cognizant_jobs.py" ;;
    eightfold)
      adapter_name="eightfold-embedded"; adapter_version="0.1.0"; adapter_script="scripts/crawl_eightfold_jobs.py" ;;
    generic_html)
      adapter_name="generic-jsonld"; adapter_version="0.1.0"; adapter_script="scripts/crawl_generic_jsonld.py" ;;
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
    paylocity)
      adapter_name="paylocity-html-json"; adapter_version="0.1.0"; adapter_script="scripts/crawl_paylocity.py" ;;
    rippling)
      adapter_name="rippling-nextjs"; adapter_version="0.1.0"; adapter_script="scripts/crawl_rippling.py" ;;
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
    export SITE_ID="$site_id"
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
  if [[ "${STRICT_CRAWL_FAILURES:-0}" == "1" ]]; then
    exit 1
  fi
  exit 0
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Some due-site crawls failed; failures are recorded in crawl_runs and career_sites." >&2
fi

if [[ "${SKIP_POST_CRAWL_TITLE_ML:-0}" != "1" ]]; then
  bash "$SCRIPT_DIR/run_post_crawl_title_classification.sh"
fi
