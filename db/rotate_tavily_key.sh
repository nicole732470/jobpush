#!/usr/bin/env bash
# Safely rotate the Tavily key used by JobPush without putting it in Git or shell history.
set -euo pipefail

REGION="${REGION:-us-east-2}"
SECRET_ID="${SECRET_ID:-joblens/app}"

if [[ ! -t 0 ]]; then
  echo "Run this script from an interactive terminal so the key can be entered securely." >&2
  exit 2
fi

read -r -s -p "New Tavily API key: " NEW_TAVILY_KEY
printf '\n'
[[ -n "$NEW_TAVILY_KEY" ]] || { echo "Key cannot be empty." >&2; exit 2; }

USAGE_JSON=$(curl -fsS https://api.tavily.com/usage \
  -H "Authorization: Bearer $NEW_TAVILY_KEY")
PLAN=$(printf '%s' "$USAGE_JSON" | jq -r '.account.current_plan // empty')
LIMIT=$(printf '%s' "$USAGE_JSON" | jq -r '.account.plan_limit // empty')
USED=$(printf '%s' "$USAGE_JSON" | jq -r '.account.plan_usage // empty')
[[ -n "$PLAN" && -n "$LIMIT" && -n "$USED" ]] || {
  echo "Tavily accepted the request but returned an unexpected usage response." >&2
  exit 1
}

TMP=$(mktemp -t jobpush-tavily-secret.XXXXXX)
trap 'rm -f "$TMP"' EXIT
chmod 600 "$TMP"

CURRENT=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" --region "$REGION" \
  --query SecretString --output text)
printf '%s' "$CURRENT" | jq --arg key "$NEW_TAVILY_KEY" \
  '.TAVILY_API_KEY = $key' > "$TMP"

aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ID" --region "$REGION" \
  --secret-string "file://$TMP" \
  --query VersionId --output text >/dev/null

unset NEW_TAVILY_KEY CURRENT USAGE_JSON
echo "Updated $SECRET_ID:TAVILY_API_KEY in $REGION (plan=$PLAN, usage=$USED/$LIMIT)."
