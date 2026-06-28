#!/usr/bin/env bash
# Deplete remaining Tavily basic-search credits across multiple user-provided
# keys without storing keys in Git or printing them to logs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REGION="${REGION:-us-east-2}"
SECRET_ID="${SECRET_ID:-joblens/app}"
RESERVE_CREDITS="${RESERVE_CREDITS:-5}"

[[ "$RESERVE_CREDITS" =~ ^[0-9]+$ ]] || {
  echo "RESERVE_CREDITS must be a non-negative integer" >&2
  exit 2
}

usage() {
  cat >&2 <<'USAGE'
Usage:
  db/deplete_tavily_keys.sh

Paste one Tavily key per line, then press Ctrl-D.

Optional environment:
  RESERVE_CREDITS=5   Keep a small reserve to avoid provider quota edge cases.
  REGION=us-east-2
  SECRET_ID=joblens/app

This script:
  1. Checks each key's /usage.
  2. Rotates AWS Secrets Manager joblens/app:TAVILY_API_KEY to that key.
  3. Runs P-tier never-searched discovery in 150/30/10-credit chunks.
  4. Never prints the key value.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -t 0 ]]; then
  echo "Paste Tavily keys, one per line. Press Ctrl-D when done." >&2
fi

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

rotate_secret_to_key() {
  local key="$1"
  local tmp
  tmp="$(mktemp -t jobpush-tavily-secret.XXXXXX)"
  chmod 600 "$tmp"
  trap 'rm -f "$tmp"' RETURN

  local current
  current="$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ID" --region "$REGION" \
    --query SecretString --output text)"

  printf '%s' "$current" | jq --arg key "$key" '.TAVILY_API_KEY = $key' > "$tmp"
  aws secretsmanager put-secret-value \
    --secret-id "$SECRET_ID" --region "$REGION" \
    --secret-string "file://$tmp" \
    --query VersionId --output text >/dev/null
}

run_chunk() {
  local chunk="$1"
  case "$chunk" in
    150)
      bash "$REPO_DIR/db/deploy_via_ssm.sh" db/run_discover_career_sites_expansion.sh
      ;;
    30)
      bash "$REPO_DIR/db/deploy_via_ssm.sh" db/run_discover_career_sites_expansion_30.sh
      ;;
    10)
      bash "$REPO_DIR/db/deploy_via_ssm.sh" db/run_discover_career_sites_expansion_10.sh
      ;;
    *)
      echo "Unsupported chunk size: $chunk" >&2
      exit 2
      ;;
  esac
}

total_planned=0
key_index=0

while IFS= read -r raw_key || [[ -n "$raw_key" ]]; do
  key="$(printf '%s' "$raw_key" | tr -d '[:space:]')"
  [[ -n "$key" ]] || continue
  key_index=$((key_index + 1))

  masked="$(mask_key "$key")"
  echo "Checking Tavily key #$key_index ($masked)..." >&2
  usage_json="$(usage_json_for_key "$key")"
  plan="$(printf '%s' "$usage_json" | jq -r '.account.current_plan // "unknown"')"
  used="$(printf '%s' "$usage_json" | jq -r '.account.plan_usage // empty')"
  limit="$(printf '%s' "$usage_json" | jq -r '.account.plan_limit // empty')"
  if [[ ! "$used" =~ ^[0-9]+$ || ! "$limit" =~ ^[0-9]+$ ]]; then
    echo "Skipping key #$key_index: unexpected Tavily usage response." >&2
    continue
  fi

  remaining=$((limit - used - RESERVE_CREDITS))
  if (( remaining < 10 )); then
    echo "Skipping key #$key_index ($masked): plan=$plan usage=$used/$limit, usable remaining <$((10 + RESERVE_CREDITS))." >&2
    continue
  fi

  echo "Using key #$key_index ($masked): plan=$plan usage=$used/$limit, planned usable credits=$remaining." >&2
  rotate_secret_to_key "$key"

  while (( remaining >= 150 )); do
    run_chunk 150
    remaining=$((remaining - 150))
    total_planned=$((total_planned + 150))
  done
  while (( remaining >= 30 )); do
    run_chunk 30
    remaining=$((remaining - 30))
    total_planned=$((total_planned + 30))
  done
  while (( remaining >= 10 )); do
    run_chunk 10
    remaining=$((remaining - 10))
    total_planned=$((total_planned + 10))
  done

  unset key usage_json raw_key
done

echo "Planned Tavily credits consumed across provided keys: $total_planned"
