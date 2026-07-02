#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
SECRET_ID="${SECRET_ID:-joblens/app}"

python3 - <<'PY'
import json
import subprocess
import urllib.request

secret = subprocess.check_output(
    [
        "aws",
        "secretsmanager",
        "get-secret-value",
        "--secret-id",
        "joblens/app",
        "--region",
        "us-east-2",
        "--query",
        "SecretString",
        "--output",
        "text",
    ],
    text=True,
)
data = json.loads(secret)

keys = []
active = str(data.get("TAVILY_API_KEY") or "").strip()
if active:
    keys.append(("active", active))
for index, key in enumerate(data.get("TAVILY_API_KEYS") or [], 1):
    key = str(key or "").strip()
    if key and key not in {existing for _, existing in keys}:
        keys.append((f"pool_{index}", key))

print(f"tavily_keys_configured={len(keys)}")
total_remaining = 0
for label, key in keys:
    masked = f"{key[:10]}...{key[-4:]}" if len(key) > 14 else "<redacted>"
    request = urllib.request.Request(
        "https://api.tavily.com/usage",
        headers={"Authorization": f"Bearer {key}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            usage = json.loads(response.read().decode())
        account = usage.get("account") or {}
        used = account.get("plan_usage")
        limit = account.get("plan_limit")
        remaining = limit - used if isinstance(used, int) and isinstance(limit, int) else None
        if isinstance(remaining, int):
            total_remaining += max(remaining, 0)
        print(
            f"{label} {masked} plan={account.get('current_plan')} "
            f"usage={used}/{limit} remaining={remaining}"
        )
    except Exception as exc:
        print(f"{label} {masked} usage_error={type(exc).__name__}: {exc}")

print(f"total_reported_remaining={total_remaining}")
PY
