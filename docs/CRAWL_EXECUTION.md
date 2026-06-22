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

Both pilots store detailed titles as `review`, record request/page metrics, and
are rerun once to verify idempotent upserts before the adapter is widened to
other verified sites of the same type.

The live US-only surface is `jobpush.job_postings_us`. The base
`jobpush.job_postings` table remains the crawl history and may also contain
out-of-market postings from a global snapshot. `career_sites.target_country_code`
records the intended market for each configured endpoint.
