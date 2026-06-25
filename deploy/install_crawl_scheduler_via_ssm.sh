#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
EC2_INSTANCE="${EC2_INSTANCE:-i-0bdee6f611283586f}"
REPO_URL="${REPO_URL:-https://github.com/nicole732470/jobpush.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/jobpush}"

SERVICE=$(base64 <<'UNIT' | tr -d '\n'
[Unit]
Description=JobPush due career-site crawl batch
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/jobpush
ExecStart=/bin/bash -lc 'git pull --ff-only origin main && bash db/run_due_crawl_batch.sh 50'
TimeoutStartSec=3600
UNIT
)

TIMER=$(base64 <<'UNIT' | tr -d '\n'
[Unit]
Description=Run JobPush due crawl check every 15 minutes during rollout

[Timer]
OnCalendar=*:0/15
RandomizedDelaySec=2m
Persistent=true
Unit=jobpush-crawl.service

[Install]
WantedBy=timers.target
UNIT
)

COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$EC2_INSTANCE" \
  --document-name AWS-RunShellScript \
  --parameters commands="[
\"set -euo pipefail\",
\"if [[ -d '$INSTALL_DIR/.git' ]]; then git -C '$INSTALL_DIR' fetch origin main && git -C '$INSTALL_DIR' checkout main && git -C '$INSTALL_DIR' pull --ff-only origin main; else git clone --branch main '$REPO_URL' '$INSTALL_DIR'; fi\",
\"echo '$SERVICE' | base64 -d > /etc/systemd/system/jobpush-crawl.service\",
\"echo '$TIMER' | base64 -d > /etc/systemd/system/jobpush-crawl.timer\",
\"systemctl daemon-reload\",
\"systemctl enable --now jobpush-crawl.timer\",
\"systemctl status jobpush-crawl.timer --no-pager\",
\"systemctl list-timers jobpush-crawl.timer --no-pager\"
]" \
  --query 'Command.CommandId' \
  --output text)

echo "SSM CommandId: $COMMAND_ID"
for _ in $(seq 1 60); do
  sleep 5
  command_status=$(aws ssm get-command-invocation \
    --region "$REGION" --command-id "$COMMAND_ID" --instance-id "$EC2_INSTANCE" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$command_status" in
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

echo "Timed out waiting for scheduler installation" >&2
exit 1
