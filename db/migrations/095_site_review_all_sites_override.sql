BEGIN;

-- Site review is an override surface, not only a queue of system-uncertain
-- rows. Show verified/auto-trusted sites as well as pending candidates, and
-- keep up to three candidates for every discovery source, including
-- ats_url_guess. This preserves Nicole's ability to compare candidates and
-- manually override a system choice later.
CREATE OR REPLACE VIEW jobpush.career_site_review_workbench AS
WITH display_candidates AS (
    SELECT
        site.*,
        row_number() OVER (
            PARTITION BY site.consolidation_key
            ORDER BY site.candidate_rank NULLS LAST,
                     site.candidate_score DESC NULLS LAST,
                     CASE site.discovery_source
                         WHEN 'ats_url_guess' THEN 0
                         WHEN 'generic_html_link_resolver' THEN 1
                         WHEN 'tavily_basic' THEN 2
                         ELSE 3
                     END,
                     site.site_id
        ) AS display_rank
    FROM jobpush.career_sites site
    WHERE site.verification_status = 'unverified'
), candidate_rollup AS (
    SELECT
        site.consolidation_key,
        count(*) AS candidate_count,
        max(site.site_id) FILTER (WHERE site.display_rank = 1) AS candidate_1_site_id,
        max(site.site_url) FILTER (WHERE site.display_rank = 1) AS candidate_1_url,
        max(site.source_type) FILTER (WHERE site.display_rank = 1) AS candidate_1_source,
        max(site.site_id) FILTER (WHERE site.display_rank = 2) AS candidate_2_site_id,
        max(site.site_url) FILTER (WHERE site.display_rank = 2) AS candidate_2_url,
        max(site.source_type) FILTER (WHERE site.display_rank = 2) AS candidate_2_source,
        max(site.site_id) FILTER (WHERE site.display_rank = 3) AS candidate_3_site_id,
        max(site.site_url) FILTER (WHERE site.display_rank = 3) AS candidate_3_url,
        max(site.source_type) FILTER (WHERE site.display_rank = 3) AS candidate_3_source
    FROM display_candidates site
    WHERE site.display_rank <= 3
    GROUP BY site.consolidation_key
), verified_ranked AS (
    SELECT
        site.*,
        row_number() OVER (
            PARTITION BY site.consolidation_key
            ORDER BY
                CASE WHEN site.crawl_enabled THEN 0 ELSE 1 END,
                site.reviewed_at DESC NULLS LAST,
                site.updated_at DESC NULLS LAST,
                site.site_id
        ) AS verified_rank
    FROM jobpush.career_sites site
    WHERE site.verification_status = 'verified'
), verified_rollup AS (
    SELECT
        site.consolidation_key,
        site.site_id AS verified_site_id,
        site.site_url AS verified_url,
        site.source_type AS verified_source
    FROM verified_ranked site
    WHERE site.verified_rank = 1
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
            WHEN verified.verified_url IS NOT NULL THEN 'VERIFIED'
            WHEN candidates.candidate_count > 0 THEN 'REVIEW_CANDIDATES'
            ELSE 'NO_CANDIDATE'
        END AS action_status,
        COALESCE(candidates.candidate_count, 0) AS candidate_count,
        candidates.candidate_1_site_id,
        candidates.candidate_1_url,
        candidates.candidate_1_source,
        candidates.candidate_2_site_id,
        candidates.candidate_2_url,
        candidates.candidate_2_source,
        candidates.candidate_3_site_id,
        candidates.candidate_3_url,
        candidates.candidate_3_source,
        verified.verified_url,
        verified.verified_source,
        verified.verified_site_id
    FROM jobpush.crawl_targets target
    JOIN jobpush.company_targets_consolidated consolidated USING (consolidation_key)
    LEFT JOIN candidate_rollup candidates USING (consolidation_key)
    LEFT JOIN verified_rollup verified USING (consolidation_key)
    WHERE target.enabled
      AND (
          candidates.candidate_count > 0
          OR verified.verified_url IS NOT NULL
      )
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
    'Human career-site override surface. One company per row; includes pending candidates and verified/auto-trusted sites; every source can expose up to three candidates.';

COMMIT;
