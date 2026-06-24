# JobPush Daily dashboard

The first dashboard is a private Streamlit app running on the existing EC2
host and reading the existing private RDS database. It is deliberately bound
to `127.0.0.1`; no public inbound port or additional server is required.

Open it from the repository directory:

```bash
bash deploy/open_dashboard_tunnel.sh
```

Keep that terminal open, then visit <http://127.0.0.1:8501>. This uses the same
AWS/SSM access already used for database deployment and does not require a
Codex token.

## Current pages

- today's new target/review jobs, closed jobs, crawl runs, and failures;
- filterable active US job list with direct links;
- personal saved/apply-next/applied/dismissed workflow;
- adapter health, recent run logs, and active alerts;
- full company-to-schedulable-site coverage funnel.

`first_seen_at` and daily boundaries are displayed using America/Chicago.
Application decisions live in `jobpush.job_application_actions`; title target
classification and personal application state remain separate.

## Deployment

```bash
bash deploy/install_dashboard_via_ssm.sh
```

The service is `jobpush-dashboard.service`. A later public-URL phase may add
Google OIDC and HTTPS, but must retain an explicit email allowlist before any
public network exposure.
