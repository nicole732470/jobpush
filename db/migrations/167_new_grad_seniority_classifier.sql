\pset pager off

BEGIN;

CREATE OR REPLACE FUNCTION jobpush.classify_job_seniority(p_normalized_title TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN lower(COALESCE(p_normalized_title, '')) ~ '(^|[^a-z])(intern(ship)?|co[ -]?op)([^a-z]|$)'
            THEN 'internship'
        WHEN (
            lower(COALESCE(p_normalized_title, '')) ~ '(^|[^a-z])(new grad(uate)?s?|new college grad(uate)?s?|recent grad(uate)?s?|university grad(uate)?s?|college grad(uate)?s?|graduate hires?|graduate roles?|graduate opportunities|graduate schemes?|graduate development programs?|graduate rotation(al)? programs?|campus hires?|university hires?|class of 20[0-9]{2}|grad(uate)?s? 20[0-9]{2})([^a-z]|$)'
            OR lower(COALESCE(p_normalized_title, '')) ~ '(^|[^a-z])(early careers?|graduate programs?)([^a-z]|$)'
        )
        AND lower(COALESCE(p_normalized_title, '')) !~ '(^|[^a-z])(recruiter|recruiting|recruitment|talent acquisition|program coordinator|program director|professor)([^a-z]|$)'
            THEN 'new_grad'
        WHEN lower(COALESCE(p_normalized_title, '')) ~ '(^|[^a-z])(entry[ -]?level|early careers?)([^a-z]|$)'
            THEN 'entry_level'
        WHEN lower(COALESCE(p_normalized_title, '')) ~ '(^|[^a-z])(senior|sr\.?|staff|principal|lead|director|vice president|vp)([^a-z]|$)'
            THEN 'senior_or_leadership'
        ELSE 'regular_full_time'
    END;
$$;

COMMIT;

SELECT title, jobpush.classify_job_seniority(title) AS seniority_bucket
FROM (VALUES
    ('software engineer new grad'),
    ('new college graduate product manager'),
    ('early career data analyst'),
    ('campus recruiter'),
    ('graduate program coordinator'),
    ('senior early talent acquisition specialist'),
    ('software engineering intern')
) examples(title);
