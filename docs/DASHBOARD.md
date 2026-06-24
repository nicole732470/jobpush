# JobPush Ops dashboard

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

- today's active-US new target/review jobs, US closed jobs, crawl runs, and failures;
- default P0/P1 active US `target` job list with direct links;
- CSV download for the current filtered job view and one-company job list;
- downloadable 100/250/500/1,000/2,000-title human review batches;
- filters for company, title/role, location, priority tier, role decision, and
  application status;
- role-stack, canonical-role, company, and location breakdowns;
- one-company job list for networking/application planning;
- personal saved/apply-next/applied/dismissed workflow;
- adapter health, recent run logs, failed run details, and active alerts;
- full company-to-schedulable-site coverage funnel, P0/P1/P2 coverage by tier,
  P0/P1/P2 company-level scoring tables, and all priority-score distributions;
- separate human-verified and system-auto-trusted site coverage.

The dashboard covers all monitored companies. `first_seen_at` and daily
boundaries are displayed using America/Chicago so "today" is consistent with
Nicole's working timezone; this is not a Chicago-company filter.
Application decisions live in `jobpush.job_application_actions`; title target
classification and personal application state remain separate.

The top-line job metrics use `jobpush.job_postings_us`, so non-US title-language
signals and inactive/closed postings do not inflate Nicole's daily recommendation
counts. If you want to audit the classifier, include `review` in the sidebar;
the default recommendation view intentionally shows `target` only.

Application status is a personal workflow, not a classifier: `new` means no
application decision, `saved` is an interesting bookmark, `apply_next` is the
shortlist, `applied` means submitted, and `dismissed` means intentionally
skipped. The dashboard explains these values in the Application queue tab.

`role_stack` is currently a dashboard-level convenience grouping derived from
`job_title_labels.classification_status`, `canonical_role`, and title text. If
the stack-1/2/3 taxonomy becomes a durable product rule, promote it into
`jobpush.job_title_labels` or a versioned config file instead of treating this
display rule as source of truth.

## Deployment

```bash
bash deploy/install_dashboard_via_ssm.sh
```

The service is `jobpush-dashboard.service`. A later public-URL phase may add
Google OIDC and HTTPS, but must retain an explicit email allowlist before any
public network exposure.
