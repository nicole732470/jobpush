#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
EC2_INSTANCE="${EC2_INSTANCE:-i-0fc6ca6a342fb0608}"
DB_INSTANCE="${DB_INSTANCE:-joblens-db}"
WAIT_FOR_STOP="${WAIT_FOR_STOP:-0}"

ec2_state="$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$EC2_INSTANCE" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)"

if [[ "$ec2_state" == "running" ]]; then
  echo "Stopping JobPush services on EC2..."
  command_id="$(aws ssm send-command \
    --region "$REGION" \
    --instance-ids "$EC2_INSTANCE" \
    --document-name AWS-RunShellScript \
    --parameters commands='[
      "pkill -f run_zero_credit_site_processing_loop\\\\.sh || true",
      "pkill -f run_due_crawl_batch\\\\.sh || true",
      "pkill -f run_structured_adapter_pilot\\\\.sh || true",
      "systemctl stop jobpush-dashboard.service 2>/dev/null || true",
      "systemctl disable --now jobpush-crawl.timer jobpush-crawl.service 2>/dev/null || true"
    ]' \
    --query 'Command.CommandId' \
    --output text)"
  aws ssm wait command-executed --region "$REGION" --command-id "$command_id" --instance-id "$EC2_INSTANCE" || true

  echo "Stopping EC2 $EC2_INSTANCE..."
  aws ec2 stop-instances --region "$REGION" --instance-ids "$EC2_INSTANCE" >/dev/null
  [[ "$WAIT_FOR_STOP" == "1" ]] && aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$EC2_INSTANCE"
else
  echo "EC2 $EC2_INSTANCE is $ec2_state; no stop needed."
fi

db_status="$(aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier "$DB_INSTANCE" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)"
if [[ "$db_status" == "available" ]]; then
  echo "Stopping RDS $DB_INSTANCE..."
  aws rds stop-db-instance --region "$REGION" --db-instance-identifier "$DB_INSTANCE" >/dev/null
  [[ "$WAIT_FOR_STOP" == "1" ]] && aws rds wait db-instance-stopped --region "$REGION" --db-instance-identifier "$DB_INSTANCE"
else
  echo "RDS $DB_INSTANCE is $db_status; no stop needed."
fi
