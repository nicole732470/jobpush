BEGIN;

-- Nicole reviewed the Tavily company-profile pilot and decided it is not useful
-- for priority scoring. Keep career-site discovery evidence, but remove the
-- separate company-profile enrichment surface to avoid confusion.
DROP VIEW IF EXISTS jobpush.company_priority_enrichment_workbench;
DROP TABLE IF EXISTS jobpush.company_external_enrichment;

COMMIT;
