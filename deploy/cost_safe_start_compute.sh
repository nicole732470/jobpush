#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
EC2_INSTANCE="${EC2_INSTANCE:-i-0bdee6f611283586f}"
DB_INSTANCE="${DB_INSTANCE:-joblens-db}"

db_status="$(aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier "$DB_INSTANCE" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)"
case "$db_status" in
  available) echo "RDS $DB_INSTANCE already available." ;;
  stopped)
    echo "Starting RDS $DB_INSTANCE..."
    aws rds start-db-instance --region "$REGION" --db-instance-identifier "$DB_INSTANCE" >/dev/null
    ;;
  starting|backing-up|configuring-*) echo "RDS $DB_INSTANCE is $db_status; waiting." ;;
  *) echo "RDS $DB_INSTANCE is $db_status; waiting but not issuing start." ;;
esac
aws rds wait db-instance-available --region "$REGION" --db-instance-identifier "$DB_INSTANCE"

ec2_state="$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$EC2_INSTANCE" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)"
case "$ec2_state" in
  running) echo "EC2 $EC2_INSTANCE already running." ;;
  stopped)
    echo "Starting EC2 $EC2_INSTANCE..."
    aws ec2 start-instances --region "$REGION" --instance-ids "$EC2_INSTANCE" >/dev/null
    ;;
  pending) echo "EC2 $EC2_INSTANCE is pending; waiting." ;;
  *) echo "EC2 $EC2_INSTANCE is $ec2_state; waiting but not issuing start." ;;
esac
aws ec2 wait instance-running --region "$REGION" --instance-ids "$EC2_INSTANCE"
aws ec2 wait instance-status-ok --region "$REGION" --instance-ids "$EC2_INSTANCE"
echo "Cost-safe compute is ready."
