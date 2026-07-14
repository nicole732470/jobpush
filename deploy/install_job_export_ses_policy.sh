#!/usr/bin/env bash
set -euo pipefail

: "${AWS_PROFILE:=jobpush-new}"
export AWS_PROFILE
ROLE_NAME="${ROLE_NAME:-joblens-ec2}"

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name JobPushDailyExportEmail \
  --policy-document file://<(cat <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["ses:SendEmail", "ses:SendRawEmail"],
    "Resource": [
      "arn:aws:ses:us-east-2:314567759747:identity/nicole732470@gmail.com",
      "arn:aws:ses:us-east-2:314567759747:identity/yuli2026@u.northwestern.edu"
    ]
  }]
}
JSON
)

echo "Installed minimal SES send policy on $ROLE_NAME"
