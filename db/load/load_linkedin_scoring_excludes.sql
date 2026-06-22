BEGIN;

TRUNCATE jobpush.linkedin_top_employer_scoring_excludes;

INSERT INTO jobpush.linkedin_top_employer_scoring_excludes (employer_key, notes)
VALUES
    ('abstract', 'Ambiguous short brand; prefix matches Abstract Security and similar'),
    ('vast', 'Ambiguous short brand'),
    ('abridge', 'Ambiguous short brand');

COMMIT;
