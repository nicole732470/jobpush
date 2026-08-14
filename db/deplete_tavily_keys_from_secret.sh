#!/usr/bin/env bash
# Run never-searched P-tier Tavily discovery against every key stored in
# joblens/app:TAVILY_API_KEYS. Designed to run on EC2 via SSM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${REGION:-us-east-2}"
SECRET_ID="${SECRET_ID:-joblens/app}"
RESERVE_CREDITS="${RESERVE_CREDITS:-25}"
MAX_PER_KEY="${MAX_PER_KEY:-0}"
TAVILY_WORKERS="${TAVILY_WORKERS:-1}"
BATCH_SIZE="${BATCH_SIZE:-150}"

[[ "$BATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || {
  echo "BATCH_SIZE must be a positive integer" >&2
  exit 2
}

mask_key() {
  local key="$1"
  local len=${#key}
  if (( len <= 12 )); then
    printf '<redacted>'
  else
    printf '%s...%s' "${key:0:10}" "${key: -4}"
  fi
}

usage_json_for_key() {
  local key="$1"
  curl -fsS https://api.tavily.com/usage \
    -H "Authorization: Bearer $key"
}

SECRET_JSON="$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" --region "$REGION" \
  --query SecretString --output text)"

mapfile -t KEYS < <(python3 - "$SECRET_JSON" <<'PY'
import json, sys
secret = json.loads(sys.argv[1])
for key in secret.get("TAVILY_API_KEYS", []):
    key = str(key).strip()
    if key:
        print(key)
PY
)
unset SECRET_JSON

if (( ${#KEYS[@]} == 0 )); then
  echo "No TAVILY_API_KEYS configured in $SECRET_ID" >&2
  exit 1
fi

total_planned=0
for i in "${!KEYS[@]}"; do
  key="${KEYS[$i]}"
  masked="$(mask_key "$key")"
  echo "Checking Tavily key $((i + 1))/${#KEYS[@]} ($masked)..."

  usage_json="$(usage_json_for_key "$key" || true)"
  used="$(printf '%s' "$usage_json" | jq -r '.account.plan_usage // empty')"
  limit="$(printf '%s' "$usage_json" | jq -r '.account.plan_limit // empty')"
  if [[ ! "$used" =~ ^[0-9]+$ || ! "$limit" =~ ^[0-9]+$ ]]; then
    echo "Skipping $masked: usage endpoint did not return numeric usage."
    continue
  fi

  remaining=$((limit - used - RESERVE_CREDITS))
  if (( MAX_PER_KEY > 0 && remaining > MAX_PER_KEY )); then
    remaining="$MAX_PER_KEY"
  fi
  if (( remaining <= 0 )); then
    echo "Skipping $masked: usage=$used/$limit, reserve=$RESERVE_CREDITS."
    continue
  fi

  echo "Running $remaining searches with $masked (usage=$used/$limit, reserve=$RESERVE_CREDITS, workers=$TAVILY_WORKERS, batch_size=$BATCH_SIZE)."
  while (( remaining > 0 )); do
    batch=$(( remaining < BATCH_SIZE ? remaining : BATCH_SIZE ))
    TAVILY_API_KEY="$key" TAVILY_WORKERS="$TAVILY_WORKERS" \
      bash "$SCRIPT_DIR/run_discover_career_sites_expansion.sh" "$batch"
    remaining=$((remaining - batch))
    total_planned=$((total_planned + batch))
  done
done

unset key KEYS
echo "Planned Tavily searches across configured keys: $total_planned"
