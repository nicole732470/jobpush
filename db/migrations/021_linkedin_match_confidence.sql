BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.linkedin_top_employer_scoring_excludes (
    employer_key    TEXT PRIMARY KEY
                    REFERENCES jobpush.linkedin_top_employers_2026(employer_key)
                    ON DELETE CASCADE,
    notes           TEXT NOT NULL DEFAULT ''
);

CREATE OR REPLACE FUNCTION jobpush.linkedin_top_employer_match_confident(
    p_employer_key TEXT,
    p_company_name TEXT,
    p_candidate_key TEXT,
    p_match_key TEXT,
    p_match_kind TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    policy_row RECORD;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM jobpush.linkedin_top_employer_scoring_excludes exclude_row
        WHERE exclude_row.employer_key = p_employer_key
    ) THEN
        RETURN FALSE;
    END IF;

    SELECT
        consolidation.policy,
        consolidation.name_allow_regex
    INTO policy_row
    FROM jobpush.company_consolidation_policies consolidation
    WHERE consolidation.employer_key = p_employer_key;

    IF policy_row.policy = 'skip' THEN
        RETURN FALSE;
    END IF;

    IF policy_row.policy = 'merge_strict' THEN
        IF policy_row.name_allow_regex IS NULL
           OR NOT (p_company_name ~* policy_row.name_allow_regex)
        THEN
            RETURN FALSE;
        END IF;
    END IF;

    RETURN jobpush.employer_match_key_matches(
        p_candidate_key,
        p_match_key,
        p_match_kind
    );
END;
$$;

COMMIT;
