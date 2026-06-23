BEGIN;

-- Rebuild the canonical workbench directly from source tables so the legacy
-- queue views can be removed without leaving a dependency chain behind.
DROP VIEW jobpush.career_site_review_workbench;

CREATE VIEW jobpush.career_site_review_workbench AS
WITH candidate_rollup AS (
    SELECT
        site.consolidation_key,
        count(*) FILTER (WHERE site.verification_status = 'unverified') AS candidate_count,
        max(site.site_id) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 1) AS candidate_1_site_id,
        max(site.site_url) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 1) AS candidate_1_url,
        max(site.source_type) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 1) AS candidate_1_source,
        max(site.site_id) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 2) AS candidate_2_site_id,
        max(site.site_url) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 2) AS candidate_2_url,
        max(site.source_type) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 2) AS candidate_2_source,
        max(site.site_id) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 3) AS candidate_3_site_id,
        max(site.site_url) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 3) AS candidate_3_url,
        max(site.source_type) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 3) AS candidate_3_source,
        min(site.site_url) FILTER (WHERE site.verification_status = 'verified') AS verified_url,
        min(site.source_type) FILTER (WHERE site.verification_status = 'verified') AS verified_source
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
), base AS (
    SELECT
        target.priority_tier,
        target.priority_source,
        target.priority_score,
        target.consolidation_key,
        target.canonical_name,
        target.discovery_status,
        consolidated.employer_city,
        consolidated.employer_state,
        consolidated.lca_count,
        consolidated.target_role_lca_count,
        consolidated.chicago_score,
        consolidated.linkedin_top_employer_score,
        CASE
            WHEN target.priority_source = 'manual_override' AND target.priority_tier = 'P0' THEN 'manual_p0'
            WHEN consolidated.chicago_score > 0 AND consolidated.linkedin_top_employer_score > 0 THEN 'chicago_and_linkedin'
            WHEN consolidated.chicago_score > 0 THEN 'chicago'
            WHEN consolidated.linkedin_top_employer_score > 0 THEN 'linkedin_top_employer'
            WHEN consolidated.lca_count >= 100 THEN 'large_lca_sponsor'
            ELSE 'score_or_diverse_sample'
        END AS potential_p0_signal,
        CASE
            WHEN rollup.verified_url IS NOT NULL THEN 'VERIFIED'
            WHEN rollup.candidate_count > 0 THEN 'REVIEW_CANDIDATES'
            ELSE 'NO_CANDIDATE'
        END AS action_status,
        COALESCE(rollup.candidate_count, 0) AS candidate_count,
        rollup.candidate_1_site_id,
        rollup.candidate_1_url,
        rollup.candidate_1_source,
        rollup.candidate_2_site_id,
        rollup.candidate_2_url,
        rollup.candidate_2_source,
        rollup.candidate_3_site_id,
        rollup.candidate_3_url,
        rollup.candidate_3_source,
        rollup.verified_url,
        rollup.verified_source
    FROM jobpush.crawl_targets target
    JOIN jobpush.company_targets_consolidated consolidated USING (consolidation_key)
    LEFT JOIN candidate_rollup rollup USING (consolidation_key)
    WHERE target.enabled
      AND (rollup.candidate_count > 0 OR rollup.verified_url IS NOT NULL)
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
    base.*
FROM base
ORDER BY review_rank;

COMMENT ON VIEW jobpush.career_site_review_workbench IS
    'Only human career-site review queue. One company per row; verified status takes precedence.';

DROP VIEW jobpush.career_site_company_review_queue_ranked;
DROP VIEW jobpush.career_site_company_dashboard;
DROP VIEW jobpush.career_site_review_workbench_v1;
DROP VIEW jobpush.career_site_review_queue;
DROP VIEW jobpush.career_site_company_review_queue;

COMMIT;
