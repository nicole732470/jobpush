#!/usr/bin/env bash
set -euo pipefail

SECRET_ID="jobpush/metabase"
ENV_DIR="/opt/metabase"
ENV_FILE="$ENV_DIR/metabase.env"

mkdir -p "$ENV_DIR"
chmod 700 "$ENV_DIR"

aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region us-east-2 \
  --query SecretString \
  --output text \
  | python3 -c '
import json
import sys

secret = json.load(sys.stdin)
values = {
    "MB_DB_TYPE": "postgres",
    "MB_DB_HOST": secret["app_db_host"],
    "MB_DB_PORT": str(secret["app_db_port"]),
    "MB_DB_DBNAME": secret["app_db_name"],
    "MB_DB_USER": secret["app_db_user"],
    "MB_DB_PASS": secret["app_db_password"],
    "MB_APPLICATION_DB_MAX_CONNECTION_POOL_SIZE": "5",
    "MB_SITE_NAME": "JobPush Data",
    "JAVA_TIMEZONE": "America/Chicago",
    "JAVA_OPTS": "-Xms256m -Xmx768m",
}
for key, value in values.items():
    print(f"{key}={value}")
' > "$ENV_FILE"
chmod 600 "$ENV_FILE"

if ! swapon --show | grep -q /swapfile; then
  if [[ ! -f /swapfile ]]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
  fi
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

docker pull metabase/metabase:latest
docker rm -f jobpush-metabase >/dev/null 2>&1 || true
docker run -d \
  --name jobpush-metabase \
  --restart unless-stopped \
  --env-file "$ENV_FILE" \
  --memory 1g \
  --memory-swap 2g \
  --publish 127.0.0.1:3000:3000 \
  --health-cmd 'curl --fail --silent http://localhost:3000/api/health || exit 1' \
  --health-interval 20s \
  --health-timeout 5s \
  --health-retries 15 \
  metabase/metabase:latest
