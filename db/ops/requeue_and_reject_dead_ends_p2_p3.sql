\pset pager off

-- 1) Requeue recently auto-trusted sites that never succeeded (next_crawl shoved into future).
-- 2) Reject no-parser / dead-end structured candidates for P2/P3 companies still not enabled.

BEGIN;

UPDATE jobpush.career_sites site
SET next_crawl_at = now(),
    crawl_status = 'pending',
    updated_at = now(),
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Requeued first crawl: never succeeded after auto-trust'
    )
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.reviewed_by = 'system:structured-ats-best-v5'
  AND site.reviewed_at >= now() - interval '7 days'
  AND site.last_success_at IS NULL
  AND site.crawl_status <> 'running'
  AND COALESCE(site.next_crawl_at, now()) > now();

UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-no-parser-dead-ends-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        CASE site.source_type
            WHEN 'talentbrew' THEN 'Rejected TalentBrew CDN/asset; not an employer board'
            WHEN 'gusto' THEN 'Rejected Gusto board while AWS crawler is Cloudflare-blocked'
            WHEN 'successfactors' THEN 'Rejected SuccessFactors identify-only/shell URL; need company board'
            WHEN 'trinethire' THEN 'Rejected TriNet Hire non-board URL'
            ELSE 'Rejected identify-only structured dead-end'
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
      site.source_type IN ('talentbrew', 'gusto')
      OR (
          site.source_type = 'successfactors'
          AND (
              site.site_url ~* 'performancemanager.*successfactors\.com'
              OR site.site_url ~* '/sf/login'
              OR site.site_url ~* 'api[0-9]*\.successfactors\.com'
              OR site.site_url ~* 'career[0-9]*\.successfactors\.com/?$'
              OR site.site_url ~* 'career[0-9]*\.successfactors\.com/career/?$'
              OR site.site_url ~* 'successfactors\.com/?$'
              OR site.site_url ~* '/careers/?$'
          )
      )
      OR (
          site.source_type = 'trinethire'
          AND site.site_url !~* 'app\.trinethire\.com/companies/[^/]+'
      )
  );

-- Normalize UltiPro JobBoard → ListJobs for remaining not-enabled companies.
UPDATE jobpush.career_sites site
SET site_url = regexp_replace(
        site.site_url,
        '^(https?://recruiting\.ultipro\.com/[^/]+/JobBoard)(?:/[0-9a-f-]{36})?.*$',
        '\1/ListJobs',
        'i'
    ),
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Normalized UltiPro board URL to ListJobs (dead-end-cleanup-v1)'
    ),
    updated_at = now()
WHERE site.source_type = 'ultipro'
  AND site.normalized_domain = 'recruiting.ultipro.com'
  AND site.verification_status = 'unverified'
  AND site.site_url ~* '^https?://recruiting\.ultipro\.com/[^/]+/JobBoard'
  AND site.site_url !~* '/JobBoard/ListJobs$'
  AND EXISTS (
      SELECT 1 FROM jobpush.crawl_targets target
      WHERE target.consolidation_key = site.consolidation_key
        AND target.enabled
        AND target.priority_tier IN ('P2','P3')
  )
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  );

COMMIT;

\echo === Requeued never-succeeded auto-trust ===
SELECT count(*) AS requeued_due
FROM jobpush.crawl_schedule_queue
WHERE is_due
  AND priority_tier IN ('P2','P3')
  AND last_success_at IS NULL;

\echo === Remaining structured not-enabled ===
WITH not_enabled AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.source_type
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.verification_status='unverified'
    AND site.source_type <> 'generic_html'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier, source_type, count(*) AS companies
FROM not_enabled
GROUP BY 1,2
ORDER BY 1, companies DESC;
