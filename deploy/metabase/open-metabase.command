#!/bin/zsh
set -e
export PATH="$HOME/.local/bin:$PATH"

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo "AWS Session Manager plugin is not installed."
  echo "Run: brew install --cask session-manager-plugin"
  read "?Press Enter to close..."
  exit 1
fi

(sleep 3; open http://localhost:3000) &
echo "Opening JobPush Metabase at http://localhost:3000"
echo "Keep this window open while using Metabase. Press Ctrl-C when finished."

aws ssm start-session \
  --target i-0bdee6f611283586f \
  --region us-east-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'
