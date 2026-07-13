\echo '=== search companies for Harvey AI ==='
SELECT fein, name, city, state, lca_count
FROM public.companies
WHERE name ILIKE '%harvey%ai%'
   OR name ILIKE '%harvey artificial%'
   OR name ILIKE 'harvey, inc%'
   OR name ILIKE 'harvey inc%'
   OR name ILIKE '%harvey%legal%'
ORDER BY lca_count DESC NULLS LAST
LIMIT 30;

\echo '=== consolidation groups named harvey ==='
SELECT group_id, canonical_name, linkedin_employer_key, policy, member_fein_count
FROM jobpush.company_consolidation_groups
WHERE canonical_name ILIKE '%harvey%'
   OR group_id ILIKE '%harvey%'
   OR linkedin_employer_key ILIKE '%harvey%';

\echo '=== linkedin top employer matches harvey ==='
SELECT *
FROM jobpush.linkedin_top_employer_company_matches
WHERE employer_key ILIKE '%harvey%'
   OR matched_name ILIKE '%harvey%'
LIMIT 20;

\echo '=== add_verified_career_site signature ==='
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'add_verified_career_site'
  AND pronamespace = 'jobpush'::regnamespace;
