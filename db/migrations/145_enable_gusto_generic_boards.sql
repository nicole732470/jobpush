BEGIN;

-- jobs.gusto.com is a recurring platform-style job board. The existing
-- generic parser can parse its job cards after title cleanup, so enable this
-- small high-signal cohort without a separate adapter.
WITH eligible AS (
    SELECT DISTINCT ON (site.consolidation_key)
        site.site_id,
        target.priority_tier
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P1','P2','P3')
      AND site.source_type = 'generic_html'
      AND site.normalized_domain = 'jobs.gusto.com'
      AND site.site_url ~* '/boards/'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
    ORDER BY site.consolidation_key,
             site.candidate_score DESC NULLS LAST,
             site.candidate_rank NULLS LAST,
             site.site_id
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
        ELSE 336
    END,
    reviewed_at = now(),
    reviewed_by = 'system:gusto-generic-parser-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Enabled jobs.gusto.com board for generic parser after title cleanup'),
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

COMMIT;

SELECT target.priority_tier, count(*) AS enabled_gusto_sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:gusto-generic-parser-v1'
GROUP BY target.priority_tier
ORDER BY target.priority_tier;

