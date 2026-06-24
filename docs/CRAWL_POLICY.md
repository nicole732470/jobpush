# JobPush crawl policy

This document is the operational rulebook for finding official career sites,
crawling them repeatedly, and deciding which jobs belong in the US target set.
All crawler writes remain in the `jobpush` schema.

## 1. Official-site acquisition

1. `crawl_targets` supplies the consolidated company identity and P tier.
2. Discovery may propose up to three URLs; generic candidates never enable themselves.
3. Prefer an official ATS/search endpoint over a corporate careers landing page.
4. Human confirmation is authoritative. Rank-1 structured ATS candidates may
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

### Current auto-trust boundary (2026-06-24)

- Candidate rank must be 1 and the company must be P0/P1.
- Greenhouse and Workday may be auto-trusted with conservative local US
  classification.
- Generic HTML, Ashby, Lever, and SmartRecruiters remain out until a supported
  adapter and precision evidence exist.
- iCIMS auto-trust was rolled back after its initial sample produced 0/3 safe
  US-scope runs. Human-confirmed iCIMS remains supported.
- The first Greenhouse/Workday expansion sample produced 43 successes and four
  Workday failures among 47 attempted sites; failures stay visible in
  `crawl_runs` and receive backoff.

## 5. Job relevance

Live titles are normalized and first matched exactly against
`soc_role_title_mappings`. Their SOC codes are then checked against
`target_soc_roles`:

- only target SOC matches: automatic `target`;
- only non-target SOC matches: automatic `non_target`;
- mixed SOC matches or no exact match: `review`;
- exact manual labels always override automatic rules;
- explicit profile hard exclusions (Lead, Staff, Principal, Director, VP,
  Chief, ML-model, mechanical/electrical/CAD/embedded/hardware boundaries) run
  before SOC suggestions and are versioned as `profile-boundary-v1`;
- every new title is evaluated by the boundary trigger at insert time, so the
  system does not send obvious exclusions back to the human queue forever.

The historical raw-title/SOC file is therefore the first labeling layer, not a
replacement for reviewing new, more detailed career-site titles.

Manual labeling and the editable workbook are documented in
[`JOB_TITLE_LABELING.md`](JOB_TITLE_LABELING.md).
