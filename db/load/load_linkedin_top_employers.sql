BEGIN;

TRUNCATE
    jobpush.linkedin_top_employer_company_matches,
    jobpush.linkedin_top_employer_match_terms,
    jobpush.linkedin_top_employers_2026
CASCADE;

COMMIT;
