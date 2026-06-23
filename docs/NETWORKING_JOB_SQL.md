# Company job list for networking

Use [`db/analysis/company_job_list_for_networking.sql`](../db/analysis/company_job_list_for_networking.sql)
directly in TablePlus. It deliberately uses three short, read-only queries:

1. enter part of a company name and find its exact `consolidation_key`;
2. paste that key to list every active US role and direct application URL;
3. use the same key to summarize hiring by role family and location.

The job list shows `target`, `review`, and `non_target` instead of silently
hiding uncertain roles. For a focused networking list, enable the documented
`<> 'non_target'` filter. Empty results mean JobPush has not yet completed a
successful crawl for that company; they do not mean the company has no jobs.
