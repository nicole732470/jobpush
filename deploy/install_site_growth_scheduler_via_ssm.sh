#!/usr/bin/env bash
set -euo pipefail

: "${AWS_PROFILE:=jobpush-new}"
export AWS_PROFILE
REGION="${REGION:-us-east-2}"
EC2_INSTANCE="${EC2_INSTANCE:-i-0fc6ca6a342fb0608}"
REPO_URL="${REPO_URL:-https://github.com/nicole732470/jobpush.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/jobpush}"

DAILY_SERVICE=$(base64 <<'UNIT' | tr -d '\n'
[Unit]
Description=JobPush zero-credit career-site growth workflow
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/jobpush
ExecStart=/bin/bash -lc 'MODE=daily bash db/run_site_growth_workflow.sh'
TimeoutStartSec=7200
UNIT
)

DAILY_TIMER=$(base64 <<'UNIT' | tr -d '\n'
[Unit]
Description=Run JobPush zero-credit site growth every day

[Timer]
OnCalendar=*-*-* 03:10:00 America/Chicago
RandomizedDelaySec=10m
Persistent=true
Unit=jobpush-site-growth.service

[Install]
WantedBy=timers.target
UNIT
)

MONTHLY_SERVICE=$(base64 <<'UNIT' | tr -d '\n'
[Unit]
Description=JobPush monthly Tavily discovery and site ingestion workflow
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/jobpush
ExecStart=/bin/bash -lc 'MODE=monthly ATS_GUESS_LIMIT=1500 GENERIC_RESOLVE_LIMIT=3000 bash db/run_site_growth_workflow.sh'
TimeoutStartSec=43200
UNIT
)

MONTHLY_TIMER=$(base64 <<'UNIT' | tr -d '\n'
[Unit]
Description=Run JobPush paid discovery after monthly Tavily quota reset

[Timer]
OnCalendar=*-*-01 02:10:00 America/Chicago
RandomizedDelaySec=10m
Persistent=true
Unit=jobpush-site-growth-monthly.service

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
\"echo '$DAILY_SERVICE' | base64 -d > /etc/systemd/system/jobpush-site-growth.service\",
\"echo '$DAILY_TIMER' | base64 -d > /etc/systemd/system/jobpush-site-growth.timer\",
\"echo '$MONTHLY_SERVICE' | base64 -d > /etc/systemd/system/jobpush-site-growth-monthly.service\",
\"echo '$MONTHLY_TIMER' | base64 -d > /etc/systemd/system/jobpush-site-growth-monthly.timer\",
\"systemctl daemon-reload\",
\"systemctl enable --now jobpush-site-growth.timer jobpush-site-growth-monthly.timer\",
\"systemctl list-timers jobpush-site-growth.timer jobpush-site-growth-monthly.timer --no-pager\"
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

echo "Timed out waiting for site-growth scheduler installation" >&2
exit 1
