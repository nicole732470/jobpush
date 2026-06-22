#!/bin/zsh
set -e
export PATH="$HOME/.local/bin:$PATH"

SECRET=$(aws secretsmanager get-secret-value \
  --secret-id jobpush/metabase \
  --region us-east-2 \
  --query SecretString \
  --output text)

echo "$SECRET" | python3 -c '
import json
import sys

secret = json.load(sys.stdin)
print("Use these values on the Add your data screen:")
print("Database type: PostgreSQL")
print("Display name: JobPush Data")
print(f"Host: {secret[\"analytics_db_host\"]}")
print(f"Port: {secret[\"analytics_db_port\"]}")
print(f"Database name: {secret[\"analytics_db_name\"]}")
print(f"Username: {secret[\"analytics_db_user\"]}")
'

echo "$SECRET" | python3 -c 'import json,sys; print(json.load(sys.stdin)["analytics_db_password"], end="")' | pbcopy
unset SECRET
echo "The read-only database password is copied to your clipboard. Paste it into Password."
echo "Create your own Metabase administrator email and password in the browser."
echo "Keep this window open during setup; press Ctrl-C when finished."

(sleep 3; open http://localhost:3000) &
aws ssm start-session \
  --target i-0bdee6f611283586f \
  --region us-east-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'
