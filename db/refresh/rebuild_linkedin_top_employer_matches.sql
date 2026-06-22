BEGIN;

TRUNCATE jobpush.linkedin_top_employer_company_matches;

INSERT INTO jobpush.linkedin_top_employer_company_matches (
    fein, employer_key, company_name, match_source, match_key, linkedin_name
)
SELECT DISTINCT
    csk.fein,
    term.employer_key,
    company_row.name,
    'search_key',
    term.match_key,
    term.linkedin_name
FROM jobpush.linkedin_top_employer_match_terms term
JOIN public.company_search_keys csk
  ON jobpush.employer_match_key_matches(
        csk.search_key, term.match_key, term.match_kind
     )
JOIN public.companies company_row
  ON company_row.fein = csk.fein
WHERE jobpush.linkedin_top_employer_match_confident(
    term.employer_key,
    company_row.name,
    csk.search_key,
    term.match_key,
    term.match_kind
);

INSERT INTO jobpush.linkedin_top_employer_company_matches (
    fein, employer_key, company_name, match_source, match_key, linkedin_name
)
SELECT DISTINCT
    alias_row.fein,
    term.employer_key,
    company_row.name,
    'company_alias',
    term.match_key,
    term.linkedin_name
FROM jobpush.linkedin_top_employer_match_terms term
JOIN public.company_aliases alias_row
  ON jobpush.employer_match_key_matches(
        jobpush.normalize_employer_match_key(alias_row.alias_name),
        term.match_key,
        term.match_kind
     )
JOIN public.companies company_row
  ON company_row.fein = alias_row.fein
WHERE jobpush.linkedin_top_employer_match_confident(
    term.employer_key,
    company_row.name,
    jobpush.normalize_employer_match_key(alias_row.alias_name),
    term.match_key,
    term.match_kind
)
ON CONFLICT DO NOTHING;

INSERT INTO jobpush.linkedin_top_employer_company_matches (
    fein, employer_key, company_name, match_source, match_key, linkedin_name
)
SELECT DISTINCT
    company_row.fein,
    term.employer_key,
    company_row.name,
    'company_name',
    term.match_key,
    term.linkedin_name
FROM jobpush.linkedin_top_employer_match_terms term
JOIN public.companies company_row
  ON jobpush.employer_match_key_matches(
        jobpush.normalize_employer_match_key(company_row.name),
        term.match_key,
        term.match_kind
     )
WHERE jobpush.linkedin_top_employer_match_confident(
    term.employer_key,
    company_row.name,
    jobpush.normalize_employer_match_key(company_row.name),
    term.match_key,
    term.match_kind
)
ON CONFLICT DO NOTHING;

COMMIT;
