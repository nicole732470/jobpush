BEGIN;

CREATE OR REPLACE FUNCTION jobpush.is_executive_level_job_title(p_title TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT lower(coalesce(p_title, '')) ~
      '(^|[^a-z])(ceo|cfo|coo|cto|cio|cmo|cro|chro|chief[[:space:]-]+([a-z]+[[:space:]-]+){0,4}officer|president|vice president|executive director|managing director|general manager|owner|founder)([^a-z]|$)';
$$;

ALTER TABLE jobpush.employer_filing_stats
    ADD COLUMN IF NOT EXISTS lca_case_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS executive_level_lca_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE jobpush.employer_filing_stats
    DROP CONSTRAINT IF EXISTS employer_filing_stats_lca_case_count_check,
    DROP CONSTRAINT IF EXISTS employer_filing_stats_executive_count_check;

ALTER TABLE jobpush.employer_filing_stats
    ADD CONSTRAINT employer_filing_stats_lca_case_count_check
        CHECK (lca_case_count >= 0),
    ADD CONSTRAINT employer_filing_stats_executive_count_check
        CHECK (executive_level_lca_count >= 0 AND executive_level_lca_count <= lca_case_count);

ALTER TABLE jobpush.company_targets_consolidated
    ADD COLUMN IF NOT EXISTS executive_only_excluded BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS priority_exclusion_reason TEXT;

COMMENT ON FUNCTION jobpush.is_executive_level_job_title(TEXT) IS
    'Conservative C-suite/executive title boundary for excluding 1-2 filing sponsors; generic manager titles do not match.';
COMMENT ON COLUMN jobpush.company_targets_consolidated.executive_only_excluded IS
    'True when the consolidated company has only 1-2 LCA filings and every filing is clearly C-suite/executive level.';

COMMIT;
