BEGIN;

-- Keep the human site-review surface compact for zero-credit ATS guesses.
-- Direct ATS guessing can produce multiple plausible structured boards for one
-- company. For manual review, expose only the strongest guessed candidate per
-- company; Tavily/manual candidates continue to expose up to three candidates.
CREATE OR REPLACE VIEW jobpush.career_site_review_workbench AS
WITH unverified AS (
    SELECT
        site.*,
        row_number() OVER (
            PARTITION BY site.consolidation_key, site.discovery_source
            ORDER BY site.candidate_rank NULLS LAST,
                     site.candidate_score DESC NULLS LAST,
                     site.site_id
        ) AS source_row_number
    FROM jobpush.career_sites site
    WHERE site.verification_status = 'unverified'
), display_candidates AS (
    SELECT
        candidate.*,
        row_number() OVER (
            PARTITION BY candidate.consolidation_key
            ORDER BY candidate.candidate_rank NULLS LAST,
                     candidate.candidate_score DESC NULLS LAST,
                     CASE candidate.discovery_source
                         WHEN 'ats_url_guess' THEN 0
                         WHEN 'generic_html_link_resolver' THEN 1
                         WHEN 'tavily_basic' THEN 2
                         ELSE 3
                     END,
                     candidate.site_id
        ) AS display_rank
    FROM unverified candidate
    WHERE candidate.discovery_source <> 'ats_url_guess'
       OR candidate.source_row_number = 1
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
), verified_rollup AS (
    SELECT
        site.consolidation_key,
        min(site.site_url) AS verified_url,
        min(site.source_type) AS verified_source
    FROM jobpush.career_sites site
    WHERE site.verification_status = 'verified'
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
        verified.verified_source
    FROM jobpush.crawl_targets target
    JOIN jobpush.company_targets_consolidated consolidated USING (consolidation_key)
    LEFT JOIN candidate_rollup candidates USING (consolidation_key)
    LEFT JOIN verified_rollup verified USING (consolidation_key)
    WHERE target.enabled
      AND (candidates.candidate_count > 0 OR verified.verified_url IS NOT NULL)
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
    'Only human career-site review queue. One company per row; verified status takes precedence; ats_url_guess exposes only one candidate per company.';

COMMIT;
