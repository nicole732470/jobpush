BEGIN;

TRUNCATE jobpush.soc_role_title_mappings;

\copy jobpush.soc_role_title_mappings (
    raw_job_title,
    normalized_soc_code,
    soc_title,
    soc_lca_count,
    raw_lca_count,
    normalized_job_title
)
FROM '/tmp/jobpush-load/soc_role_title_mappings.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COMMIT;
