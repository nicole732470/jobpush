# Cost-safe AWS operating mode

Goal: keep JobPush usable while stretching the remaining AWS credit through `2027-01-07`.

## What changed

- The old hourly crawl schedule is disabled in `.github/workflows/crawl-due-sites.yml`.
- `.github/workflows/cost-safe-daily-crawl.yml` now runs once daily at `12:15 UTC` (`07:15 America/Chicago` during daylight time).
- The daily workflow:
  1. starts RDS `joblens-db`;
  2. starts EC2 `i-0bdee6f611283586f`;
  3. runs one bounded due-site crawl batch, default `500` sites;
  4. stops dashboard/background crawl services;
  5. stops EC2 and RDS.

## Manual commands

Start compute:

```bash
bash deploy/cost_safe_start_compute.sh
```

Run one daily batch through SSM:

```bash
bash db/deploy_via_ssm.sh db/run_cost_safe_daily_crawl.sh
```

Stop compute:

```bash
bash deploy/cost_safe_stop_compute.sh
```

Install/update the GitHub Actions AWS permissions:

```bash
bash deploy/install_cost_safe_github_policy.sh
```

## Cost rule

Default mode should be “off unless actively crawling.”  Keep RDS and EC2 running only during the daily crawl window or while actively debugging/deploying the dashboard.

Do not run the legacy all-day crawl loop unless explicitly doing a short test.
