\pset pager off

-- Conservative scale-up for generic career pages.
-- This intentionally does not try to parse every corporate site. It enables
-- only the best careers/jobs-looking generic page per company, excludes known
-- aggregators/noisy domains, and lets the existing generic parser prove value.

BEGIN;

WITH best_site_per_company AS (
    SELECT DISTINCT ON (site.consolidation_key)
        site.site_id,
        target.priority_tier,
        target.priority_score,
        COALESCE(site.candidate_score, 0) AS candidate_score
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P1', 'P2', 'P3')
      AND site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND COALESCE(site.candidate_score, 0) >= :'min_candidate_score'::numeric
      AND (
          site.site_url ILIKE '%/careers%'
          OR site.site_url ILIKE '%/career%'
          OR site.site_url ILIKE '%/jobs%'
          OR site.site_url ILIKE '%/job%'
      )
      AND site.normalized_domain !~* '(^|\.)(h1bvisajobs|justia\.jobs|careersinfood|selectleaders|directlyapply|remotive|purpose\.jobs|employbl|edtechjobs|milwaukeejobs|usnlx|jsfirm|nbmbaa|careercenter\.rxinsider|jobs-redefined)\.'
      AND site.site_url !~* '/(login|privacy|terms|faq|blog|news|press|events|article|membership|employer|company/[^/]+$)'
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
),
eligible AS (
    SELECT site_id, priority_tier
    FROM best_site_per_company
    ORDER BY CASE priority_tier WHEN 'P1' THEN 0 WHEN 'P2' THEN 1 ELSE 2 END,
             priority_score DESC,
             candidate_score DESC,
             site_id
    LIMIT :'limit'::int
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
        WHEN 'P3' THEN 336
        ELSE 168
    END,
    reviewed_at = now(),
    reviewed_by = 'system:generic-html-conservative-wave-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Conservative generic HTML enablement: best high-score careers/jobs page; parser still requires US evidence'),
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

UPDATE jobpush.crawl_targets target
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE EXISTS (
    SELECT 1
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.verification_status = 'verified'
      AND site.reviewed_by = 'system:generic-html-conservative-wave-v1'
);

COMMIT;

SELECT target.priority_tier,
       count(*) AS enabled_sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:generic-html-conservative-wave-v1'
  AND site.crawl_enabled
GROUP BY target.priority_tier
ORDER BY target.priority_tier;

