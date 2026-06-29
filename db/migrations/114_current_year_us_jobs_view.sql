BEGIN;

CREATE OR REPLACE FUNCTION jobpush.posting_is_current_year(
    p_posted_text TEXT,
    p_reference_date DATE DEFAULT current_date
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    WITH value AS (
        SELECT btrim(coalesce(p_posted_text, '')) AS text_value
    ), parsed AS (
        SELECT
            CASE
                WHEN text_value ~ '^[0-9]{13}$'
                    THEN EXTRACT(YEAR FROM to_timestamp((text_value::numeric / 1000.0)))::int
                WHEN text_value ~ '^[0-9]{10}$'
                    THEN EXTRACT(YEAR FROM to_timestamp(text_value::bigint))::int
                WHEN regexp_match(text_value, '(^|[^0-9])(20[0-9]{2})([^0-9]|$)') IS NOT NULL
                    THEN (regexp_match(text_value, '(^|[^0-9])(20[0-9]{2})([^0-9]|$)'))[2]::int
                ELSE NULL
            END AS posted_year
        FROM value
    )
    SELECT posted_year IS NULL OR posted_year = EXTRACT(YEAR FROM p_reference_date)::int
    FROM parsed;
$$;

CREATE OR REPLACE VIEW jobpush.job_postings_us AS
SELECT posting.*
FROM jobpush.job_postings posting
WHERE posting.active
  AND posting.market_scope = 'US'
  AND jobpush.posting_is_current_year(posting.posted_text);

COMMIT;

SELECT
    COUNT(*) FILTER (WHERE active AND market_scope = 'US') AS active_us_jobs_raw,
    COUNT(*) FILTER (
        WHERE active
          AND market_scope = 'US'
          AND jobpush.posting_is_current_year(posted_text)
    ) AS active_us_current_year_jobs,
    COUNT(*) FILTER (
        WHERE active
          AND market_scope = 'US'
          AND NOT jobpush.posting_is_current_year(posted_text)
    ) AS active_us_old_posted_jobs_excluded
FROM jobpush.job_postings;
