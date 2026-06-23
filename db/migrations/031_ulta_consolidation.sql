BEGIN;

INSERT INTO jobpush.linkedin_top_employers_2026 (
    employer_key, linkedin_name, best_rank, appearance_count, regions,
    source_url, source_year, notes
)
VALUES (
    'ulta', 'Ulta', 999, 1, '',
    '', 2026, 'Manual consolidation anchor for Ulta retail entities'
)
ON CONFLICT (employer_key) DO UPDATE SET
    linkedin_name = EXCLUDED.linkedin_name,
    notes = EXCLUDED.notes;

INSERT INTO jobpush.company_consolidation_policies (
    employer_key, linkedin_name, policy, min_feins,
    name_allow_regex, name_deny_regex, notes
)
VALUES (
    'ulta', 'Ulta', 'merge_strict', 2,
    '^(ulta[, ]|ulta beauty)', NULL,
    'Ulta retail entities only; avoids consultancy false positives'
)
ON CONFLICT (employer_key) DO UPDATE SET
    linkedin_name = EXCLUDED.linkedin_name,
    policy = EXCLUDED.policy,
    min_feins = EXCLUDED.min_feins,
    name_allow_regex = EXCLUDED.name_allow_regex,
    name_deny_regex = EXCLUDED.name_deny_regex,
    notes = EXCLUDED.notes;

INSERT INTO jobpush.linkedin_top_employer_company_matches (
    fein, employer_key, company_name, match_source, match_key, linkedin_name
)
VALUES
    (
        '46-1142752', 'ulta', 'Ulta, Inc.', 'manual',
        'ulta', 'Ulta'
    ),
    (
        '36-4832212', 'ulta', 'Ulta Beauty Credit Services Corporation', 'manual',
        'ulta', 'Ulta'
    )
ON CONFLICT (fein, employer_key, match_source, match_key) DO UPDATE SET
    company_name = EXCLUDED.company_name,
    linkedin_name = EXCLUDED.linkedin_name;

COMMIT;
