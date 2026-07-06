#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
ROLE_NAME="${ROLE_NAME:-JobPushGitHubActionsSSMRole}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
INSTANCE_ID="${EC2_INSTANCE:-i-0bdee6f611283586f}"
DB_INSTANCE="${DB_INSTANCE:-joblens-db}"

POLICY="$(jq -cn \
  --arg region "$REGION" \
  --arg account "$ACCOUNT_ID" \
  --arg instance "$INSTANCE_ID" \
  --arg db "$DB_INSTANCE" \
  '{
    Version:"2012-10-17",
    Statement:[
      {
        Sid:"DispatchOnlyToJobPushHost",
        Effect:"Allow",
        Action:["ssm:SendCommand"],
        Resource:[
          ("arn:aws:ssm:"+$region+"::document/AWS-RunShellScript"),
          ("arn:aws:ec2:"+$region+":"+$account+":instance/"+$instance)
        ]
      },
      {
        Sid:"ReadCommandResult",
        Effect:"Allow",
        Action:["ssm:GetCommandInvocation","ssm:ListCommandInvocations"],
        Resource:"*"
      },
      {
        Sid:"CostSafeEc2Control",
        Effect:"Allow",
        Action:[
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ],
        Resource:"*"
      },
      {
        Sid:"CostSafeRdsControl",
        Effect:"Allow",
        Action:[
          "rds:StartDBInstance",
          "rds:StopDBInstance",
          "rds:DescribeDBInstances"
        ],
        Resource:"*"
      }
    ]
  }')"

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name JobPushCostSafeDailyCrawl \
  --policy-document "$POLICY"

echo "Installed cost-safe GitHub policy on $ROLE_NAME"
