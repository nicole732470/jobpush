#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-2}"
REPOSITORY="${REPOSITORY:-nicole732470/jobpush}"
ROLE_NAME="${ROLE_NAME:-JobPushGitHubActionsSSMRole}"
INSTANCE_ID="${EC2_INSTANCE:-i-0bdee6f611283586f}"
OIDC_URL="https://token.actions.githubusercontent.com"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider \
    --url "$OIDC_URL" \
    --client-id-list sts.amazonaws.com >/dev/null
fi

TRUST_POLICY="$(jq -cn \
  --arg provider "$PROVIDER_ARN" \
  --arg subject "repo:${REPOSITORY}:ref:refs/heads/main" \
  '{Version:"2012-10-17",Statement:[{Effect:"Allow",Principal:{Federated:$provider},Action:"sts:AssumeRoleWithWebIdentity",Condition:{StringEquals:{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com","token.actions.githubusercontent.com:sub":$subject}}}]}')"

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST_POLICY"
else
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --description "GitHub Actions OIDC role for JobPush production crawl dispatch" \
    --assume-role-policy-document "$TRUST_POLICY" >/dev/null
fi

PERMISSIONS_POLICY="$(jq -cn \
  --arg document "arn:aws:ssm:${REGION}::document/AWS-RunShellScript" \
  --arg instance "arn:aws:ec2:${REGION}:${ACCOUNT_ID}:instance/${INSTANCE_ID}" \
  '{Version:"2012-10-17",Statement:[{Sid:"DispatchOnlyToJobPushHost",Effect:"Allow",Action:"ssm:SendCommand",Resource:[$document,$instance]},{Sid:"ReadCommandResult",Effect:"Allow",Action:"ssm:GetCommandInvocation",Resource:"*"}]}')"

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name JobPushDispatchCrawlViaSSM \
  --policy-document "$PERMISSIONS_POLICY"

echo "$ROLE_ARN"
