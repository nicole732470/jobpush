#!/bin/zsh
set -e
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

REGION="us-east-2"
EC2_INSTANCE="i-0bdee6f611283586f"
RDS_HOST="joblens-db.chu86icsovrl.us-east-2.rds.amazonaws.com"
LOCAL_PORT="15432"

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo "Session Manager plugin is not installed."
  echo "Double-click install-session-manager.command first."
  read "?Press Enter to close..."
  exit 1
fi

cleanup() {
  if [[ -n "${TUNNEL_PID:-}" ]] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Opening encrypted tunnel to RDS on 127.0.0.1:${LOCAL_PORT} ..."
aws ssm start-session \
  --target "$EC2_INSTANCE" \
  --region "$REGION" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$RDS_HOST\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" &
TUNNEL_PID=$!

for _ in {1..30}; do
  if nc -z 127.0.0.1 "$LOCAL_PORT" 2>/dev/null; then
    break
  fi
  sleep 1
done

if ! nc -z 127.0.0.1 "$LOCAL_PORT" 2>/dev/null; then
  echo "Tunnel did not become ready on port ${LOCAL_PORT}."
  echo "Check AWS credentials and Session Manager plugin install."
  exit 1
fi

SECRET=$(aws secretsmanager get-secret-value \
  --secret-id joblens/rds \
  --region "$REGION" \
  --query SecretString \
  --output text)

DB_USER=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["username"])' "$SECRET")
DB_PASS=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["password"])' "$SECRET")
DB_NAME=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["database"])' "$SECRET")
unset SECRET

ENCODED_USER=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$DB_USER")
ENCODED_PASS=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$DB_PASS")
CONN_URL="postgresql://${ENCODED_USER}:${ENCODED_PASS}@127.0.0.1:${LOCAL_PORT}/${DB_NAME}?sslmode=require"
echo "$DB_PASS" | pbcopy
unset DB_PASS ENCODED_USER ENCODED_PASS

echo
echo "Tunnel is ready. Password copied to clipboard."
echo
echo "TablePlus connection:"
echo "  Host: 127.0.0.1"
echo "  Port: ${LOCAL_PORT}"
echo "  User: ${DB_USER}"
echo "  Database: ${DB_NAME}"
echo "  SSL mode: REQUIRE"
echo
echo "If TablePlus does not open automatically:"
echo "  1. Click Create a new connection -> PostgreSQL"
echo "  2. Choose Import from URL"
echo "  3. Paste the connection URL printed below"
echo
echo "$CONN_URL"
echo
echo "Keep this window open while browsing. Press Ctrl-C when finished."
echo

if [[ -d /Applications/TablePlus.app ]]; then
  (sleep 2; open -a TablePlus "$CONN_URL") &
else
  echo "TablePlus is not installed. Run: brew install --cask tableplus"
fi

wait "$TUNNEL_PID"
