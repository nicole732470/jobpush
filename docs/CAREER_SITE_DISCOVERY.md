# Career-site discovery pilot

## Cohort and cost

The first pilot covers every consolidated company with `priority_score >= 4.5`:

- Companies: 103
- Successful searches: 103
- Effective pilot search credits: 103
- Additional cancelled dry-run searches: 26
- Total Tavily basic-search credits consumed: approximately 129
- Tavily basic search cost: one credit per company

No LLM or browser rendering is used. Tavily returns candidates; it does not
verify or enable them.

## Pilot result

After automatic removal of known aggregators and external job boards:

- Companies with candidates awaiting review: 100
- Companies with no retained candidate: 3
- Review candidates: 245
- Verified sites: 0 until human review
- Crawl-enabled sites: 0 until human review

Candidate source distribution:

| Source | Candidates |
|---|---:|
| Generic official-looking HTML | 210 |
| Workday | 21 |
| Greenhouse | 7 |
| iCIMS | 3 |
| Lever | 3 |
| SmartRecruiters | 1 |

## TablePlus review workflow

Open schema `jobpush`, then view
`career_site_company_review_queue_ranked`. It shows one company per row with up
to three candidate URLs and sorts manual P0 first, followed by P1/P2 score.

`career_site_company_dashboard` is the unified status view. It deliberately
keeps completed verified companies visible, so manual P0 companies such as
Google do not disappear after review.

Review candidate 1 first. If it is wrong, inspect candidate 2 and candidate 3.
The detailed one-row-per-URL view is `career_site_review_queue`.

Confirm a site:

```sql
SELECT jobpush.review_career_site(
    12345, 'verified', 'nicole', 'Official company career or ATS site'
);
```

Reject a site:

```sql
SELECT jobpush.review_career_site(
    12345, 'rejected', 'nicole', 'Aggregator, wrong entity, or unrelated brand'
);
```

Replace `12345` with the candidate site ID shown in the review view. Confirming
a site enables it for future crawling and marks the company `found`. Rejecting
one candidate keeps the company in review while other candidates remain.

## Generalization loop

1. Human-review the 100 pilot companies.
2. Measure rank-1 precision and source-specific precision.
3. Add recurring false domains to
   `career_site_discovery_domain_excludes` and the Python deny list.
4. Add adapters for confirmed ATS sources.
5. Run a stratified 4.0/3.0/2.5 sample; only low-confidence candidates require
   human review.

Human review is a calibration sample, not a requirement for every company.
`career_site_review_precision` measures verified/rejected precision by source
type and candidate rank. Auto-verification may be enabled later only for a
narrow structured-ATS segment after it has enough reviewed examples and at
least 98% observed precision. Generic HTML and conflicting candidates remain
manual.

## Effective-tier expansion (2026-06-23)

The first expansion searched 150 never-searched P-tier companies, with manual
P0 first and high-score P1/P2 after it. It used 150 Tavily basic credits,
completed with zero search errors, and retained 381 candidates. The ranked
company review queue then contained 2 P0 and 221 P1 companies.

Known external aggregators such as TechFetch belong in both the database domain
exclude table and `scripts/discover_career_sites.py`; they must never be
verified as a company-owned career site.

`career_site_discovery_runs` records company counts, candidates, errors, and
estimated credits for every completed batch.
