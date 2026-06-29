# JobPush crawl policy

This document is the operational rulebook for finding official career sites,
crawling them repeatedly, and deciding which jobs belong in the US target set.
All crawler writes remain in the `jobpush` schema.

## 1. Official-site acquisition

1. `crawl_targets` supplies the consolidated company identity and P tier.
2. Discovery may propose up to three URLs; generic candidates never enable themselves.
3. Prefer an official ATS/search endpoint over a corporate careers landing page.
4. Human confirmation is authoritative. Best supported structured ATS candidates may
   also enter a versioned `system:*` auto-trust cohort after an adapter health
   gate; this prevents human review from becoming a one-company-at-a-time
   scaling requirement.
5. Aggregators and unrelated job boards are rejected and added to
   `career_site_discovery_domain_excludes` plus the discovery-code deny list.
6. A country-filtered official URL should be saved when available.

Candidate generation and TablePlus review details are in
[`CAREER_SITE_DISCOVERY.md`](CAREER_SITE_DISCOVERY.md).

## 2. United States scope is mandatory

Every production-enabled adapter must declare `target_country_code = 'US'`
and one `scope_method`:

| Method | Meaning |
|---|---|
| `server_filter` | Official URL/API is filtered to United States before results are returned |
| `local_filter` | API returns more countries; adapter filters using structured country/office IDs |
| `verified_us_only` | The verified endpoint itself is known to publish only US roles |
| `unknown` | Not production-ready; do not schedule automatically |

Priority order is server filter, structured local filter, verified US-only, and
finally `unknown`. Text guessing is not sufficient when structured location or
office identifiers exist.

`jobpush.crawl_scope_readiness` shows which verified sites satisfy this rule.

## 3. Snapshot and comparison rules

- `job_postings` keeps the source snapshot/history; `job_postings_us` is the
  active US business surface.
- `job_postings_us` includes only active US-scope postings whose `posted_text`
  is not explicitly from a prior year. Blank/relative dates are kept; explicit
  old years are excluded from New Jobs / Jobs to apply.
- Identity is `(site_id, external_job_id)`, never title text.
- A complete run upserts seen jobs and closes jobs missing from the same scope.
- A US run may close only prior US jobs. It must never close overseas jobs that
  were simply outside the request.
- Ambiguous locations become `unknown`, not US and not automatically closed.
- Greenhouse and Workday global feeds use conservative per-posting location
  classification. Only explicit US/state evidence enters `job_postings_us`;
  ambiguous locations remain `unknown` for review.
- Run scope and method are copied into `crawl_runs` for audit.

## 4. Scheduling and batches

P tier chooses ordering and eventual frequency; it does not change parsing.
Production intervals are P0 every 24 hours, P1 every 72 hours, and P2 every
168 hours. GitHub Actions checks hourly, but a site enters the run queue
only when all of these are true:

- `verification_status = 'verified'` came from either a human decision or an
  auditable, versioned structured-ATS auto-trust rule;
- `crawl_enabled = true`;
- `target_country_code = 'US'` and `scope_method <> 'unknown'`;
- `source_type` has a production adapter;
- `next_crawl_at <= now()`.

`verified` means the URL belongs to the intended company. It does not by itself
mean that JobPush has an adapter or a safe US filter. `crawl_schedule_queue`
enforces the full gate.

Every batch records targets, requests, pages, latency, parsed jobs, duplicates,
new/updated/closed jobs, target/review counts, and errors. Expand an adapter to
more companies only after a representative site passes a second idempotent run.

### Current auto-trust boundary (updated 2026-06-27)

- Candidate rank should generally be 1. A controlled rank-2 rollout is allowed
  only for supported structured ATS domains when the company has no verified
  site and the adapter has a safe US-scoping strategy.
- Greenhouse and Workday may be auto-trusted with conservative local US
  classification.
- Lever, Ashby, and SmartRecruiters now have public-API adapters. Best
  supported P0/P1/P2/P3 candidates can enter controlled auto-trust when no
  verified site already exists; crawl health and entity mismatch remain
  rollback gates.
- Workable, Jobvite, Paylocity, Rippling, and selected Eightfold boards have
  low-cost static/API-style parsers and can be promoted in small structured
  batches.
- Company-specific adapters with explicit US server filters, such as Amazon
  Jobs and Cognizant Jobs, can be auto-enabled when no verified site exists.
- High-volume career platforms such as Eightfold and Apple must keep any
  verified URL's country/function/query filters when crawling. Example:
  Starbucks Eightfold URLs should preserve `location=United States` and
  `filter_job_function=Project/Product/Program Management,Business Systems,Application Development`
  so store-service roles do not dominate crawl cost or the application queue.
- Big-board adapters also have hard safety caps. Oracle Cloud and Eightfold
  default to 300 parsed jobs per crawl; Apple defaults to 10 API pages. Raise
  those only after a board proves its source-side filters are tight enough.
- Expansion work is template/platform-first, not tier-first. P0/P1/P2/P3 only
  decide ordering and crawl frequency; parser work should target the same
  website family across the whole pool. Cost-first order: existing supported
  ATS candidates, generic-page hidden ATS resolver, deterministic ATS URL
  guessing, then search-provider discovery. If a company has no retained site
  candidates, parser work alone cannot expand it.
- When one company has multiple enabled sites for the same company-specific
  adapter, keep one canonical site and disable the duplicate sites so jobs are
  not repeated in the dashboard.
- Generic HTML remains outside broad automatic promotion. A limited pilot may
  enable high-score P1 pages only when the parser can extract explicit US job
  links; expand it by measured batches, not by blanket verification.
- iCIMS remains conservative: if a United States location option exists, the
  adapter uses it; otherwise it crawls the public search page and classifies
  each posting's location locally. This prevents a whole site from failing just
  because it does not expose a standardized country dropdown.
- The first Greenhouse/Workday expansion sample produced 43 successes and four
  Workday failures among 47 attempted sites; failures stay visible in
  `crawl_runs` and receive backoff.
- `career_site_selection_candidates` is the explainable selection surface; it
  records selected/review/rejected reasoning instead of hiding site choice in
  scheduler code.
- Scheduled crawls must pass `site_id` through to the adapter runner. The
  execution unit is `(site_id, external_job_id)`, not just
  `(company, source_type)`, because one company can have multiple candidate
  sites on the same ATS.

## 5. Job relevance

Live titles are normalized and first matched exactly against
`soc_role_title_mappings`. Their SOC codes are then checked against
`target_soc_roles`:

- only target SOC matches: automatic `target`;
- only non-target SOC matches: automatic `non_target`;
- mixed SOC matches or no exact match: `review`;
- exact manual labels always override automatic rules;
- executable profile title rules (`profile-title-rules-v2`) now run before SOC
  suggestions for both target tracks and avoid tracks;
- every new title is evaluated by the profile trigger at insert time, so the
  system does not send obvious target/avoid cases back to the human queue
  forever.
- Current hard avoid families include senior/leadership, hardware/embedded/ML
  research, HR, accounting/tax/audit, retail/in-store, manufacturing/factory,
  restaurant/food service, medical/therapy/lab support, buyer/procurement,
  non-technical sales, producer/media, teacher/education, warehouse/logistics,
  aerospace/aviation, and actor/dancer/performance roles.

The historical raw-title/SOC file is therefore the first labeling layer, not a
replacement for reviewing new, more detailed career-site titles.

Manual labeling and the editable workbook are documented in
[`JOB_TITLE_LABELING.md`](JOB_TITLE_LABELING.md).
