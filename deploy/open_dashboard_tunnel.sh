#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
EC2_INSTANCE="${EC2_INSTANCE:-i-0bdee6f611283586f}"
LOCAL_PORT="${LOCAL_PORT:-8501}"

if [[ -x "$HOME/.local/bin/session-manager-plugin" ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "Keep this terminal open, then visit http://127.0.0.1:${LOCAL_PORT}"
exec aws ssm start-session \
  --region "$REGION" \
  --target "$EC2_INSTANCE" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=8501,localPortNumber=${LOCAL_PORT}"
