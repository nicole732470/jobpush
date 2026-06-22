BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.soc_role_title_mappings (
    raw_job_title         TEXT NOT NULL,
    normalized_soc_code   TEXT NOT NULL,
    soc_title             TEXT NOT NULL,
    soc_lca_count         INTEGER NOT NULL DEFAULT 0 CHECK (soc_lca_count >= 0),
    raw_lca_count         INTEGER NOT NULL DEFAULT 0 CHECK (raw_lca_count >= 0),
    normalized_job_title  TEXT NOT NULL,
    source                TEXT NOT NULL DEFAULT 'LCA_All_Job_Roles_Summary.xlsx',
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (raw_job_title, normalized_soc_code),
    CHECK (normalized_soc_code ~ '^[0-9]{8}$')
);

CREATE INDEX IF NOT EXISTS idx_jobpush_soc_role_title_mappings_soc
    ON jobpush.soc_role_title_mappings(normalized_soc_code);

CREATE INDEX IF NOT EXISTS idx_jobpush_soc_role_title_mappings_normalized_title
    ON jobpush.soc_role_title_mappings(normalized_job_title);

COMMIT;
