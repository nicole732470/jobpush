BEGIN;

CREATE OR REPLACE FUNCTION jobpush.company_name_is_consolidation_denied(company_name TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM jobpush.company_consolidation_name_denies deny_row
        WHERE lower(COALESCE(company_name, '')) LIKE '%' || lower(deny_row.deny_pattern) || '%'
    );
$$;

TRUNCATE jobpush.company_consolidation_members, jobpush.company_consolidation_groups;

CREATE TEMP TABLE tmp_matched_candidates ON COMMIT DROP AS
SELECT DISTINCT
    policy.employer_key,
    policy.linkedin_name,
    policy.policy,
    policy.min_feins,
    policy.name_allow_regex,
    policy.notes,
    match_row.fein,
    company_row.name AS company_name,
    company_row.lca_count
FROM jobpush.company_consolidation_policies policy
JOIN jobpush.linkedin_top_employer_company_matches match_row
  ON match_row.employer_key = policy.employer_key
JOIN public.companies company_row
  ON company_row.fein = match_row.fein
WHERE policy.policy <> 'skip'
  AND NOT jobpush.company_name_is_consolidation_denied(company_row.name)
  AND (
      policy.policy = 'merge_all'
      OR (
          policy.policy = 'merge_strict'
          AND policy.name_allow_regex IS NOT NULL
          AND lower(company_row.name) ~* policy.name_allow_regex
      )
  );

INSERT INTO jobpush.company_consolidation_groups (
    group_id, canonical_name, linkedin_employer_key, policy, member_fein_count, notes
)
SELECT
    candidate.employer_key,
    candidate.linkedin_name,
    candidate.employer_key,
    candidate.policy,
    COUNT(*)::INTEGER AS member_fein_count,
    MIN(candidate.notes) AS notes
FROM tmp_matched_candidates candidate
GROUP BY candidate.employer_key, candidate.linkedin_name, candidate.policy
HAVING COUNT(*) >= MIN(candidate.min_feins);

INSERT INTO jobpush.company_consolidation_members (
    group_id, fein, company_name, lca_count
)
SELECT
    candidate.employer_key,
    candidate.fein,
    candidate.company_name,
    candidate.lca_count
FROM tmp_matched_candidates candidate
JOIN jobpush.company_consolidation_groups grp
  ON grp.group_id = candidate.employer_key;

COMMIT;
