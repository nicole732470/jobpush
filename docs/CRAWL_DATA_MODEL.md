# Crawl data model

JobPush separates company analysis from operational website discovery and job
crawling. All crawler writes stay in the `jobpush` schema.

## Current company tables

| Table | Rows at migration 023 | Role | Crawler writes? |
|---|---:|---|---|
| `jobpush.company_targets` | 69,250 | Legacy per-FEIN audit and sponsorship evidence | No |
| `jobpush.company_targets_consolidated` | 68,958 | Canonical company analysis, score, and P tier | No |
| `jobpush.crawl_targets` | 19,142 | Operational P0/P1/P2 company discovery queue | Yes |
| `jobpush.career_sites` | 0 initially | Verified corporate/career/ATS endpoints | Yes |
| `public.company_websites` | 0 | JobLens/shared reserved website table | **Never from JobPush** |

`company_targets` still has historical `crawl_status`, `last_crawled_at`, and
`next_crawl_at` columns. They are not the active crawl queue because that table
is one row per FEIN rather than one row per consolidated company.

## Relationships

```text
company_targets_consolidated (analysis source of truth)
    1 ── 0..1 crawl_targets (company discovery/scheduling state)
              1 ── 0..N career_sites (corporate, careers, or ATS endpoints)
```

`crawl_targets.consolidation_key` is the stable company identifier. Company
name is a display snapshot, never the key. A foreign key is intentionally not
created from `crawl_targets` to `company_targets_consolidated` because the
analysis refresh truncates and rebuilds the consolidated table.

## Queue synchronization

`db/refresh/sync_crawl_targets.sql`:

- inserts newly eligible P0/P1/P2 companies;
- updates name, tier, and score for existing companies;
- preserves discovery attempts, errors, and timestamps;
- disables companies that leave all active P tiers instead of deleting their
  crawl history.

The sync runs automatically after the consolidated scoring refresh. It can also
run alone:

```bash
bash db/deploy_via_ssm.sh db/run_sync_crawl_targets.sh
```

## Discovery and crawl responsibilities

`crawl_targets` owns company-level website discovery state. `career_sites` owns
site-level verification, source adapter, frequency, conditional-request cache,
and failure state. Frequency remains nullable until P-tier policies are approved.

The initial migration intentionally does not add blank site rows. A site record
is created only when a real candidate URL is discovered. The company queue is
already complete because every active P-tier company is present in
`crawl_targets`.

## Discovery pilot and manual review

Migration 024 adds candidate evidence and discovery-run audit tables. Migration
025 adds aggregator exclusions, the review queues, and
`jobpush.review_career_site(...)`. See
[`CAREER_SITE_DISCOVERY.md`](CAREER_SITE_DISCOVERY.md) for the 4.5+ pilot and
TablePlus review workflow.
