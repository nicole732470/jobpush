#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
EC2_INSTANCE="${EC2_INSTANCE:-i-0bdee6f611283586f}"
PUBLIC_HOST="${PUBLIC_HOST:-jobpush.3-128-164-130.sslip.io}"
UPSTREAM="${UPSTREAM:-127.0.0.1:8501}"
DASHBOARD_USER="${DASHBOARD_USER:-nicole}"

if [[ -z "${DASHBOARD_PASSWORD:-}" ]]; then
  DASHBOARD_PASSWORD="$(python3 - <<'PY'
import secrets,string
alphabet=string.ascii_letters+string.digits
print("".join(secrets.choice(alphabet) for _ in range(18)))
PY
)"
fi

COMMANDS=$(python3 - "$PUBLIC_HOST" "$UPSTREAM" "$DASHBOARD_USER" "$DASHBOARD_PASSWORD" <<'PY'
import base64
import json
import sys

host, upstream, user, password = sys.argv[1:5]
template = f"""
3-128-164-130.sslip.io {{
\treverse_proxy 127.0.0.1:8000
}}

{host} {{
\tencode gzip
\tbasic_auth {{
\t\t{user} __HASH__
\t}}
\treverse_proxy {upstream}
}}
""".lstrip()
payload = base64.b64encode(template.encode()).decode()
remote = f"""
set -euo pipefail
HASH=$(sudo /usr/local/bin/caddy hash-password --plaintext '{password}')
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%Y%m%d%H%M%S)
echo {payload} | base64 -d | sed "s|__HASH__|$HASH|" | sudo tee /etc/caddy/Caddyfile >/dev/null
sudo /usr/local/bin/caddy fmt --overwrite /etc/caddy/Caddyfile
sudo /usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
sleep 2
curl -fsSI -u '{user}:{password}' https://{host} >/dev/null
echo JOBPUSH_DASHBOARD_URL=https://{host}
echo JOBPUSH_DASHBOARD_USER={user}
echo JOBPUSH_DASHBOARD_PASSWORD={password}
"""
print(json.dumps({"commands": [remote]}))
PY
)

COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$EC2_INSTANCE" \
  --document-name AWS-RunShellScript \
  --parameters "$COMMANDS" \
  --query Command.CommandId \
  --output text)

echo "SSM CommandId: $COMMAND_ID"
for _ in $(seq 1 60); do
  sleep 5
  status=$(aws ssm get-command-invocation \
    --region "$REGION" --command-id "$COMMAND_ID" --instance-id "$EC2_INSTANCE" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$status" in
    Success)
      aws ssm get-command-invocation \
        --region "$REGION" --command-id "$COMMAND_ID" --instance-id "$EC2_INSTANCE" \
        --query '{Stdout:StandardOutputContent,Stderr:StandardErrorContent}' --output json
      exit 0 ;;
    Failed|Cancelled|TimedOut)
      aws ssm get-command-invocation \
        --region "$REGION" --command-id "$COMMAND_ID" --instance-id "$EC2_INSTANCE" \
        --output json
      exit 1 ;;
  esac
done

echo "Timed out waiting for dashboard exposure" >&2
exit 1
