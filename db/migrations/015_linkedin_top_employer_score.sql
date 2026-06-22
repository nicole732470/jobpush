BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.linkedin_top_employers_2026 (
    employer_key      TEXT PRIMARY KEY,
    linkedin_name     TEXT NOT NULL,
    best_rank         INTEGER NOT NULL CHECK (best_rank > 0),
    appearance_count  INTEGER NOT NULL CHECK (appearance_count > 0),
    regions           TEXT NOT NULL DEFAULT '',
    source_url        TEXT NOT NULL DEFAULT '',
    source_year       INTEGER NOT NULL DEFAULT 2026,
    notes             TEXT NOT NULL DEFAULT '',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS jobpush.linkedin_top_employer_match_terms (
    employer_key   TEXT NOT NULL
                   REFERENCES jobpush.linkedin_top_employers_2026(employer_key)
                   ON DELETE CASCADE,
    linkedin_name  TEXT NOT NULL,
    match_key      TEXT NOT NULL,
    match_kind     TEXT NOT NULL CHECK (match_kind IN ('exact', 'prefix')),
    term_source    TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (employer_key, match_key, match_kind)
);

CREATE TABLE IF NOT EXISTS jobpush.linkedin_top_employer_company_matches (
    fein           TEXT NOT NULL
                   REFERENCES public.companies(fein) ON DELETE CASCADE,
    employer_key   TEXT NOT NULL
                   REFERENCES jobpush.linkedin_top_employers_2026(employer_key)
                   ON DELETE CASCADE,
    company_name   TEXT NOT NULL,
    match_source   TEXT NOT NULL,
    match_key      TEXT NOT NULL,
    linkedin_name  TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (fein, employer_key, match_source, match_key)
);

CREATE INDEX IF NOT EXISTS idx_linkedin_top_employer_matches_fein
    ON jobpush.linkedin_top_employer_company_matches(fein);

CREATE OR REPLACE FUNCTION jobpush.normalize_employer_match_key(input TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT trim(
        BOTH '-'
        FROM regexp_replace(
            regexp_replace(
                lower(regexp_replace(COALESCE(input, ''), '&', ' and ', 'g')),
                '[^a-z0-9\s-]', ' ', 'g'
            ),
            '\s+', '-', 'g'
        )
    );
$$;

CREATE OR REPLACE FUNCTION jobpush.employer_match_key_matches(
    candidate_key TEXT,
    match_key TEXT,
    match_kind TEXT
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN match_kind = 'exact' THEN candidate_key = match_key
        ELSE candidate_key = match_key
          OR candidate_key LIKE match_key || '-%'
    END;
$$;

CREATE OR REPLACE FUNCTION jobpush.is_linkedin_top_employer_2026(p_fein TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM jobpush.linkedin_top_employer_company_matches match_row
        WHERE match_row.fein = p_fein
    );
$$;

ALTER TABLE jobpush.company_targets
    ADD COLUMN IF NOT EXISTS linkedin_top_employer_score NUMERIC(3, 1) NOT NULL DEFAULT 0;

ALTER TABLE jobpush.company_targets
    DROP CONSTRAINT IF EXISTS company_targets_linkedin_top_employer_score_check;

ALTER TABLE jobpush.company_targets
    ADD CONSTRAINT company_targets_linkedin_top_employer_score_check
    CHECK (linkedin_top_employer_score >= 0);

COMMIT;
