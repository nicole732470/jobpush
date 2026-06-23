BEGIN;

ALTER VIEW jobpush.career_site_review_workbench
    RENAME TO career_site_review_workbench_v1;

CREATE VIEW jobpush.career_site_review_workbench AS
WITH corrected AS (
    SELECT
        old.priority_tier,
        old.priority_source,
        old.priority_score,
        old.consolidation_key,
        old.canonical_name,
        old.discovery_status,
        old.employer_city,
        old.employer_state,
        old.lca_count,
        old.target_role_lca_count,
        old.chicago_score,
        old.linkedin_top_employer_score,
        old.potential_p0_signal,
        CASE
            WHEN old.verified_url IS NOT NULL THEN 'VERIFIED'
            WHEN old.candidate_count > 0 THEN 'REVIEW_CANDIDATES'
            ELSE 'NO_CANDIDATE'
        END AS action_status,
        old.candidate_count,
        old.candidate_1_site_id,
        old.candidate_1_url,
        old.candidate_1_source,
        old.candidate_2_site_id,
        old.candidate_2_url,
        old.candidate_2_source,
        old.candidate_3_site_id,
        old.candidate_3_url,
        old.candidate_3_source,
        old.verified_url,
        old.verified_source
    FROM jobpush.career_site_review_workbench_v1 old
)
SELECT
    row_number() OVER (
        ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
                 CASE action_status WHEN 'REVIEW_CANDIDATES' THEN 0 WHEN 'VERIFIED' THEN 1 ELSE 2 END,
                 CASE potential_p0_signal
                     WHEN 'manual_p0' THEN 0
                     WHEN 'chicago_and_linkedin' THEN 1
                     WHEN 'chicago' THEN 2
                     WHEN 'linkedin_top_employer' THEN 3
                     WHEN 'large_lca_sponsor' THEN 4
                     ELSE 5
                 END,
                 priority_score DESC,
                 md5(consolidation_key)
    ) AS review_rank,
    corrected.*
FROM corrected
ORDER BY review_rank;

COMMENT ON VIEW jobpush.career_site_review_workbench IS
    'Canonical human review surface. VERIFIED takes precedence over stale unverified candidates.';

COMMIT;
