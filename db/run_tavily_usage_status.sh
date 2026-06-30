#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
SECRET_ID="${SECRET_ID:-joblens/app}"

SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" --region "$REGION" \
  --query SecretString --output text)

TAVILY_API_KEY=$(python3 -c \
  'import json,sys; print(json.loads(sys.argv[1]).get("TAVILY_API_KEY", ""))' \
  "$SECRET")
unset SECRET

[[ -n "$TAVILY_API_KEY" ]] || { echo "TAVILY_API_KEY is not configured" >&2; exit 1; }

USAGE_JSON=$(curl -fsS https://api.tavily.com/usage \
  -H "Authorization: Bearer $TAVILY_API_KEY")
unset TAVILY_API_KEY

python3 -c '
import json, sys
data = json.load(sys.stdin)
account = data.get("account") or {}
print("plan=" + str(account.get("current_plan")))
print("usage=" + str(account.get("plan_usage")) + "/" + str(account.get("plan_limit")))
for key in ("search_usage", "crawl_usage", "extract_usage", "map_usage", "research_usage", "paygo_usage", "paygo_limit"):
    print(f"{key}={account.get(key)}")
print("raw_keys=" + ",".join(sorted(account.keys())))
' <<< "$USAGE_JSON"
