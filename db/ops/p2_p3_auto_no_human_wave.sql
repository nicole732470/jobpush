\pset pager off

-- Fully automated P2/P3 remainder cleanup (no human review):
-- 1) Reject known-bad identify-only shapes (CDN / login shell / error pages)
-- 2) Canonicalize + auto-trust Eightfold tenant /careers boards (parser already works)
-- 3) Auto-trust the one Cognizant careers URL if present

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Reject shapes that can never become crawl boards without new discovery.
-- ---------------------------------------------------------------------------
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-identify-only-dead-ends-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        CASE
            WHEN site.source_type = 'eightfold'
                AND (site.site_url ILIKE '%vs-errors.eightfold.ai%'
                     OR site.site_url ILIKE '%eightfold.ai/privacy%'
                     OR site.normalized_domain = 'eightfold.ai')
                THEN 'Rejected Eightfold privacy/error/marketing URL'
            WHEN site.source_type = 'eightfold'
                AND site.normalized_domain LIKE '%.eightfold.ai'
                AND site.site_url !~* '/careers'
                THEN 'Rejected Eightfold non-careers tenant URL'
            WHEN site.source_type = 'talentbrew'
                THEN 'Rejected TalentBrew CDN/asset host; not an employer board'
            WHEN site.source_type = 'successfactors'
                AND (
                    site.site_url ~* 'performancemanager.*successfactors\.com'
                    OR site.site_url ~* '/sf/login'
                    OR site.site_url ~* 'career[0-9]*\.successfactors\.com/?$'
                    OR site.site_url ~* 'career[0-9]*\.successfactors\.com/career/?$'
                )
                THEN 'Rejected SuccessFactors login/career shell; need company-specific board URL'
            WHEN site.source_type = 'trinethire'
                AND site.site_url ~* 'app\.trinethire\.com/companies/?$'
                THEN 'Rejected TriNet Hire companies index; need /companies/{slug} board'
            ELSE 'Rejected identify-only dead-end URL'
        END
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.verification_status = 'unverified'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'nicole%'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'manual%'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
  AND (
      (
          site.source_type = 'eightfold'
          AND (
              site.site_url ILIKE '%vs-errors.eightfold.ai%'
              OR site.site_url ILIKE '%eightfold.ai/privacy%'
              OR site.normalized_domain = 'eightfold.ai'
              OR (
                  site.normalized_domain LIKE '%.eightfold.ai'
                  AND site.site_url !~* '/careers'
              )
          )
      )
      OR site.source_type = 'talentbrew'
      OR (
          site.source_type = 'successfactors'
          AND (
              site.site_url ~* 'performancemanager.*successfactors\.com'
              OR site.site_url ~* '/sf/login'
              OR site.site_url ~* 'career[0-9]*\.successfactors\.com/?$'
              OR site.site_url ~* 'career[0-9]*\.successfactors\.com/career/?$'
          )
      )
      OR (
          site.source_type = 'trinethire'
          AND site.site_url ~* 'app\.trinethire\.com/companies/?$'
      )
  );

-- ---------------------------------------------------------------------------
-- 2) Canonicalize Eightfold tenant URLs to https://{tenant}.eightfold.ai/careers
-- ---------------------------------------------------------------------------
WITH detail AS (
    SELECT
        site.site_id,
        site.consolidation_key,
        'https://' || site.normalized_domain || '/careers' AS board_url,
        row_number() OVER (
            PARTITION BY site.consolidation_key, site.normalized_domain
            ORDER BY site.candidate_score DESC NULLS LAST, site.site_id
        ) AS keep_rank
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P2', 'P3')
      AND site.verification_status = 'unverified'
      AND site.source_type = 'eightfold'
      AND site.normalized_domain LIKE '%.eightfold.ai'
      AND site.normalized_domain <> 'eightfold.ai'
      AND site.site_url ~* '/careers'
      AND COALESCE(site.reviewed_by, '') NOT LIKE 'nicole%'
      AND COALESCE(site.reviewed_by, '') NOT LIKE 'manual%'
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
), updated AS (
    UPDATE jobpush.career_sites site
    SET site_url = detail.board_url,
        site_kind = 'ats_feed',
        source_type = 'eightfold',
        source_key = site.normalized_domain,
        review_notes = concat_ws(
            '; ',
            site.review_notes,
            'Canonicalized Eightfold tenant careers URL (auto-no-human-v1)'
        ),
        updated_at = now()
    FROM detail
    WHERE site.site_id = detail.site_id
      AND detail.keep_rank = 1
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites existing
          WHERE existing.consolidation_key = site.consolidation_key
            AND existing.site_url = detail.board_url
            AND existing.site_id <> site.site_id
      )
    RETURNING site.site_id
)
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-identify-only-dead-ends-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Rejected duplicate Eightfold careers URL after canonicalize'
    ),
    updated_at = now()
FROM detail
WHERE site.site_id = detail.site_id
  AND NOT EXISTS (SELECT 1 FROM updated WHERE updated.site_id = site.site_id);

-- ---------------------------------------------------------------------------
-- 3) Auto-trust Eightfold + Cognizant safe boards.
-- ---------------------------------------------------------------------------
WITH supported AS (
    SELECT
        site.site_id,
        site.consolidation_key,
        site.candidate_rank,
        site.candidate_score
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P2', 'P3')
      AND site.verification_status = 'unverified'
      AND (
          (
              site.source_type = 'eightfold'
              AND site.normalized_domain LIKE '%.eightfold.ai'
              AND site.normalized_domain <> 'eightfold.ai'
              AND site.site_url ~* '^https://[^/]+\.eightfold\.ai/careers/?$'
          )
          OR (
              site.source_type = 'cognizant_jobs'
              AND site.normalized_domain = 'careers.cognizant.com'
              AND site.site_url ~* '/jobs'
          )
      )
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
      )
), eligible AS (
    SELECT DISTINCT ON (consolidation_key) site_id
    FROM supported
    ORDER BY consolidation_key, candidate_rank NULLS LAST, candidate_score DESC NULLS LAST, site_id
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'system:structured-ats-best-v5',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Auto-trusted Eightfold/Cognizant board without human review (auto-no-human-v1)'
    ),
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
      AND site.crawl_enabled
      AND site.review_notes LIKE '%auto-no-human-v1%'
);

UPDATE jobpush.career_sites site
SET crawl_interval_hours = CASE target.priority_tier
        WHEN 'P2' THEN 168
        WHEN 'P3' THEN 336
        ELSE site.crawl_interval_hours
    END,
    next_crawl_at = COALESCE(site.next_crawl_at, now()),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.review_notes LIKE '%auto-no-human-v1%';

COMMIT;

\echo '=== Rejected dead-ends by source ==='
SELECT source_type, count(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_by = 'system:reject-identify-only-dead-ends-v1'
GROUP BY 1
ORDER BY sites DESC;

\echo '=== Newly auto-trusted this wave ==='
SELECT source_type, count(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_by = 'system:structured-ats-best-v5'
  AND review_notes LIKE '%auto-no-human-v1%'
GROUP BY 1
ORDER BY sites DESC;

\echo '=== Remaining structured unverified rank-1 ==='
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.source_type
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P2','P3')
    AND site.verification_status = 'unverified'
    AND site.source_type <> 'generic_html'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites enabled
      WHERE enabled.consolidation_key = site.consolidation_key
        AND enabled.verification_status = 'verified'
        AND enabled.crawl_enabled
    )
  ORDER BY site.consolidation_key,
           site.candidate_rank NULLS LAST,
           site.candidate_score DESC NULLS LAST,
           site.site_id
)
SELECT priority_tier, source_type, count(*) AS companies
FROM rank1
GROUP BY 1, 2
ORDER BY 1, companies DESC;
