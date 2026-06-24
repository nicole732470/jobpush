#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
EC2_INSTANCE="${EC2_INSTANCE:-i-0bdee6f611283586f}"
REPO_URL="${REPO_URL:-https://github.com/nicole732470/jobpush.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/jobpush}"

SERVICE=$(base64 <<'UNIT' | tr -d '\n'
[Unit]
Description=Private JobPush daily dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/jobpush/app
ExecStart=/opt/jobpush/deploy/run_dashboard.sh
Restart=on-failure
RestartSec=5
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT
)

COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$EC2_INSTANCE" \
  --document-name AWS-RunShellScript \
  --parameters commands="[
\"set -euo pipefail\",
\"if [[ -d '$INSTALL_DIR/.git' ]]; then git -C '$INSTALL_DIR' fetch origin main && git -C '$INSTALL_DIR' checkout main && git -C '$INSTALL_DIR' pull --ff-only origin main; else git clone --branch main '$REPO_URL' '$INSTALL_DIR'; fi\",
\"python3 -m venv '$INSTALL_DIR/.venv-dashboard'\",
\"'$INSTALL_DIR/.venv-dashboard/bin/pip' install --quiet --upgrade pip\",
\"'$INSTALL_DIR/.venv-dashboard/bin/pip' install --quiet -r '$INSTALL_DIR/app/requirements.txt'\",
\"chmod +x '$INSTALL_DIR/deploy/run_dashboard.sh'\",
\"echo '$SERVICE' | base64 -d > /etc/systemd/system/jobpush-dashboard.service\",
\"systemctl daemon-reload\",
\"systemctl enable --now jobpush-dashboard.service\",
\"systemctl restart jobpush-dashboard.service\",
\"sleep 5\",
\"systemctl status jobpush-dashboard.service --no-pager\",
\"curl --fail --silent http://127.0.0.1:8501/_stcore/health\"
]" \
  --query 'Command.CommandId' \
  --output text)

echo "SSM CommandId: $COMMAND_ID"
for _ in $(seq 1 120); do
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

echo "Timed out waiting for dashboard installation" >&2
exit 1
