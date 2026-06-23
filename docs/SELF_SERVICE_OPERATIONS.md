# Self-service TablePlus operations

Use [`db/manual/SELF_SERVICE_OPERATIONS.sql`](../db/manual/SELF_SERVICE_OPERATIONS.sql)
when Codex is unavailable. The file contains copy-paste SQL for:

1. finding a company's exact `consolidation_key`;
2. saving an official career URL found manually;
3. setting a persistent manual P0/P1/P2 tier;
4. rejecting all current candidates;
5. confirming which candidate is correct;
6. checking whether the site is actually crawl-ready.

These operations call database functions rather than editing several tables
independently. They immediately update RDS. GitHub stores the function
definitions and reusable examples; individual manual decisions are production
data and are not automatically committed to GitHub.

## Verified does not always mean scheduled

An official URL can safely be stored with `source_type = 'unknown'` and
`scope_method = 'unknown'`. It remains excluded from automatic crawling until
the system knows both a supported adapter and a safe US-scoping method. Do not
mark a global website `verified_us_only` merely to make it enter the queue.
