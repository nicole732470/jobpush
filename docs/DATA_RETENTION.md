# JobPush data retention

JobPush keeps enough job history to detect new and closed postings, but it
should not preserve every low-value posting forever.

## Storage layers

| Layer | Table / view | Keep? | Why |
|---|---|---:|---|
| Raw crawl history | `jobpush.job_postings` | Yes, but pruned | Needed for de-dupe, `first_seen_at`, `last_seen_at`, and closed detection. |
| Active US surface | `jobpush.job_postings_us` | View only | Current-year active US postings only. No extra storage. |
| Application queue | `jobpush.dashboard_jobs` | View only | Target/review/non-target status joined from title labels and profile rules. No extra storage. |
| Application decisions | `jobpush.job_application_actions` | Keep | Nicole's saved/apply-next/applied/dismissed state. |
| Title learning | `jobpush.job_title_labels`, history, ML tables | Keep | Manual labels and model/rule evidence. |
| Crawl operations | `jobpush.crawl_runs`, `career_sites` | Keep summarized rows | Needed to debug coverage and parser quality. |

## Why not just use time windows?

A pure time-window crawl cannot reliably tell whether a posting is new or
closed. JobPush needs the previous snapshot for each site:

```text
last crawl had job A + current crawl has job A  -> still active
last crawl had job A + current crawl missing A -> closed
last crawl missing job B + current crawl has B -> newly discovered
```

So active postings stay in `job_postings`, including non-target ones. Closed
low-value postings can be pruned after they are no longer useful for debugging
or model training.

## Retention policy

| Posting bucket | Policy |
|---|---|
| Active postings | Never delete automatically. They are needed for the next closed-job comparison. |
| Target postings | Keep, especially if open or manually saved/applied. |
| Any posting with `job_application_actions` | Never delete automatically. |
| Closed `non_target` postings | Delete after 30 days. |
| Closed non-US / unknown-scope postings | Delete after 30 days. |
| Closed `review` postings | Delete after 180 days. |
| Closed `target` postings | Keep for now; revisit after application workflow stabilizes. |
| Huge boards such as Eightfold / Apple | Prefer source-side filters before storage. Do not crawl/store whole retail boards when URL/API filters can limit country/function/query. |

Before storage, the shared adapter loader drops postings that are clearly
outside the application pool: non-US rows and description snippets that
explicitly say the employer will not sponsor visas. This keeps obvious noise
out of `job_postings`; a richer sponsorship flag can be added later only for
already-target/review jobs that justify full description fetching.

This is intentionally conservative: it reduces obvious bloat without risking
the application queue or crawl diff logic.

## Commands

Report only:

```bash
bash db/deploy_via_ssm.sh db/run_job_posting_retention_report.sh
```

Apply deletion:

```bash
APPLY_RETENTION_DELETE=true bash db/deploy_via_ssm.sh db/run_prune_job_postings_retention.sh
```

The prune script prints candidate counts before deleting. Keep it manual until
we see stable daily crawler behavior.
