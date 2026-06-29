# Crawl execution and adapter pilot

JobPush starts crawling with small, measurable batches. P tier decides which
companies are attempted first; a verified `career_sites` row decides which
adapter can safely run.

## Minimum execution model

```text
crawl_targets 1 ── N career_sites
                       │
                       ├── crawl_batch_targets ── crawl_batches
                       ├── crawl_runs
                       └── job_postings ── job_title_labels
                                           │
                                           └── job_title_catalog (view)
```

- `crawl_batches`: cohort, completion counts, requests, jobs, and final status.
- `crawl_runs`: one adapter attempt, including pages, latency, parse/dedupe,
  closed jobs, and errors.
- `job_postings`: unique by site and external job ID. A posting missing from a
  complete later crawl becomes inactive.
- `job_title_labels`: human/rule decision for a normalized detailed title.
- `job_title_catalog`: observed title frequencies plus the current label.

New titles start as `review`; the adapter does not guess relevance. Detailed
title labeling and later generalization can therefore use real crawl output.

Retention is documented in [`DATA_RETENTION.md`](DATA_RETENTION.md). In short:
active rows are kept for future closed-job detection; old closed non-target,
non-US, and long-stale review rows can be pruned by the manual retention script.

## HERE iCIMS Batch 0

HERE North America is a manually verified P0 company with a verified public
iCIMS endpoint. The `icims-html` adapter requests embedded result pages and
uses no browser, search API, or model.

```bash
bash db/deploy_via_ssm.sh db/run_migration_038.sh
bash db/deploy_via_ssm.sh db/run_here_icims_pilot.sh
```

The pilot is deliberately one company. Before expanding an adapter cohort,
inspect parse coverage, duplicates, closures, request count, latency, and the
title review queue.

## Structured adapter representatives

Migration 039 adds a US market scope and `jobpush.job_postings_us`. Two more
public ATS adapters use the same batch/run/posting loader:

- `greenhouse-api`: Strata is the representative Greenhouse board.
- `workday-cxs`: Grubhub is the representative Workday site.
- `oracle-cloud-rest`: JPMorgan is the representative Oracle Recruiting Cloud
  site; the adapter discovers and applies the United States location facet.
- `apple-jobs-api`: Apple uses its own public search API. It is already limited
  to the United States, fetches search summaries only, and uses four workers
  because Apple fixes the response size at 20 jobs per page.
- `lever-api`: Lever public postings API, with local US market classification.
- `ashby-posting-api`: Ashby public job-board API, including compensation when
  the board exposes it.
- `smartrecruiters-api`: SmartRecruiters public company-postings API with
  paginated normalization.
- `ats-url-guess`: zero-credit discovery helper, not a crawler adapter. It
  probes public Greenhouse, Lever, Ashby, and SmartRecruiters APIs with
  conservative company/domain slugs, stores candidates as
  `discovery_source='ats_url_guess'`, then relies on the normal structured-ATS
  auto-trust and adapter crawl path.
- `generic-jsonld`: conservative parser for `generic_html` career pages. It
  tries standard `schema.org/JobPosting` JSON-LD first, then a small fallback
  that accepts only job links with explicit nearby US location text and no
  nearby non-US marker. It fetches one page and uses no browser.

Both pilots store detailed titles as `review`, record request/page metrics, and
are rerun once to verify idempotent upserts before the adapter is widened to
other verified sites of the same type.

For free ATS expansion, use this order:

```bash
bash db/deploy_via_ssm.sh db/run_guess_ats_sites_500.sh
bash db/deploy_via_ssm.sh db/run_remove_dangerous_ats_url_guess_slugs.sh
bash db/deploy_via_ssm.sh db/run_ats_url_guess_audit.sh
bash db/deploy_via_ssm.sh db/run_apply_career_site_auto_trust.sh
bash db/deploy_via_ssm.sh db/run_due_crawl_batch_120.sh
```

Do not skip the cleanup/audit step. Guessed slugs are cheaper than Tavily but
can still create wrong-company candidates if generic aliases slip through.

Additional zero/low-credit discovery fallbacks, mainly for later P2 expansion:

- Avoid direct Google scraping at scale; it is CAPTCHA/IP-block prone.
- DuckDuckGo HTML can be used for small batches:
  `https://html.duckduckgo.com/html/?q={company}+careers`. Parse returned
  links, then pass them through the existing `classify_url` and cleanup flow.
- Bing Search API is a quota-based fallback. Verify the current free quota
  before use, reserve it for high-score companies with no retained candidate,
  and log estimated credits in `career_site_discovery_runs`.
- LinkedIn company jobs pages may reveal an "Apply on company website" domain,
  but LinkedIn is anti-scraping sensitive. Use only for tiny/manual batches with
  browser-like headers and never as the default high-volume path.

For stubborn `generic_html` P1 blockers, use the cheap steps before writing
company-specific parsers:

```bash
bash db/deploy_via_ssm.sh db/run_resolve_generic_html_ats_links_1000.sh
bash db/deploy_via_ssm.sh db/run_promote_generic_jsonld_sites_1000.sh
bash db/deploy_via_ssm.sh db/run_generic_blocker_template_audit.sh
bash db/deploy_via_ssm.sh db/run_p1_generic_hidden_ats_detail.sh
```

The resolver checks both anchor tags and embedded HTML/JS URLs. The JSON-LD
probe promotes only pages that expose standard `JobPosting` data. Both use zero
Tavily credits.

When hidden ATS details find employer-specific Greenhouse boards, validate a
small sample with `scripts/crawl_greenhouse.py` first, then use:

```bash
bash db/deploy_via_ssm.sh db/run_promote_p1_hidden_greenhouse_sites.sh
bash db/deploy_via_ssm.sh db/run_due_crawl_greenhouse_10.sh
bash db/deploy_via_ssm.sh db/run_p1_hidden_greenhouse_promotion_status.sh
```

Do not promote ATS vendor root pages such as `jobs.smartrecruiters.com/`,
generic Oracle CandidateExperience roots, or `ashbyhq.com/careers`; those are
not employer-specific job feeds.

Migration 117 is a 25-site P1 pilot for the generic HTML fallback; migration
118 adds that source type to the shared schedule queue. Keep this small until
crawl output quality is checked; generic pages are messy and should not be
mass-enabled just because they return HTTP 200.

Migration 068 adds `career_site_selection_candidates`, which exposes every
site-selection score and decision. Rank-1 P0/P1 Lever, Ashby, and
SmartRecruiters candidates may be auto-trusted only when no verified site
already exists. Human verified/rejected decisions remain authoritative, and
404/entity-mismatch failures must be rolled back during rollout.

Greenhouse URLs may contain `offices[]` filters. The public jobs API ignores
that query parameter, so adapter version 0.2 reads the office ID from the
verified URL and filters each API job by its returned office ID/parent ID.
StackAdapt uses this path for its United States office group.

The live US-only surface is `jobpush.job_postings_us`. The base
`jobpush.job_postings` table remains the crawl history and may also contain
out-of-market postings from a global snapshot. `career_sites.target_country_code`
records the intended market for each configured endpoint.

Exact live-title matches against the historical raw-title/SOC mapping are
applied by migration 046. `job_title_soc_match_candidates` explains every
suggestion; `job_title_review_queue` contains only unresolved titles and is the
safe TablePlus surface to export for manual labeling. Manual decisions are
never overwritten by the automatic rule.

## Production scheduler and monitoring

Migration 048 adds `crawl_schedule_queue`, `crawl_adapter_health`, and
`crawl_site_alerts`. The due runner is:

```bash
bash db/run_due_crawl_batch.sh 10
```

GitHub Actions workflow `.github/workflows/crawl-due-sites.yml` is the
production scheduler. It checks hourly, then dispatches the existing batch to
EC2 through SSM. GitHub receives no stored AWS access key: it assumes a
repository-and-main-branch-scoped OIDC role created by
`deploy/setup_github_actions_oidc.sh`.

The hourly check is cheap; actual requests occur only at the P-tier interval.
Successful runs advance `next_crawl_at`. Failed runs use exponential backoff
capped at 24 hours. The former EC2 `jobpush-crawl.timer` must remain disabled
while GitHub Actions is active so a batch is never dispatched twice.

The first scheduled production batch on 2026-06-23 completed 7/7 sites without
failure. Five adapter types had a 100% trailing-seven-day success rate and no
active alerts after the batch.

```bash
bash db/deploy_via_ssm.sh db/run_crawl_operations_dashboard.sh
```
