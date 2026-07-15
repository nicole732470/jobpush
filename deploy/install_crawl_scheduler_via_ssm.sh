#!/usr/bin/env bash
set -euo pipefail

: "${AWS_PROFILE:=jobpush-new}"
export AWS_PROFILE
REGION="${REGION:-us-east-2}"
EC2_INSTANCE="${EC2_INSTANCE:-i-0fc6ca6a342fb0608}"
REPO_URL="${REPO_URL:-https://github.com/nicole732470/jobpush.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/jobpush}"

SERVICE=$(base64 <<'UNIT' | tr -d '\n'
[Unit]
Description=JobPush nightly due career-site crawl drain
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/jobpush
ExecCondition=/bin/bash -lc 'if [[ -e /var/lib/jobpush/skip-next-crawl ]]; then rm -f /var/lib/jobpush/skip-next-crawl; exit 1; fi'
ExecStart=/usr/bin/flock -n /run/jobpush-crawl.lock /bin/bash db/run_due_crawl_drain.sh
TimeoutStartSec=43200
UNIT
)

TIMER=$(base64 <<'UNIT' | tr -d '\n'
[Unit]
Description=Run JobPush due-site crawl drain nightly at 1 AM Chicago time

[Timer]
OnCalendar=*-*-* 01:00:00 America/Chicago
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
\"if [[ ! -d '$INSTALL_DIR/.git' ]]; then git clone --branch main '$REPO_URL' '$INSTALL_DIR'; fi\",
\"mkdir -p /var/lib/jobpush\",
\"echo '$SERVICE' | base64 -d > /etc/systemd/system/jobpush-crawl.service\",
\"echo '$TIMER' | base64 -d > /etc/systemd/system/jobpush-crawl.timer\",
\"systemctl daemon-reload\",
\"systemctl enable jobpush-crawl.timer\",
\"systemctl restart jobpush-crawl.timer\",
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
