\pset pager off

-- P2/P3 structured remainder wave (no Tavily):
-- 1) Workday job-detail → parent board URL, then eligible for auto-trust
-- 2) Amazon job-detail → reject (not a company board)
-- 3) UltiPro JobBoard → ListJobs when possible
-- 4) Auto-trust remaining safe structured boards
-- 5) Retry failed first crawls for system:generic-jsonld-v1

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Canonicalize Workday job-detail URLs to the parent board.
-- ---------------------------------------------------------------------------
WITH detail AS (
    SELECT
        site.site_id,
        site.consolidation_key,
        regexp_replace(site.site_url, '/job/.*$', '', 'i') AS board_url,
        row_number() OVER (
            PARTITION BY site.consolidation_key,
                         regexp_replace(site.site_url, '/job/.*$', '', 'i')
            ORDER BY site.candidate_score DESC NULLS LAST, site.site_id
        ) AS keep_rank
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P2', 'P3')
      AND site.verification_status = 'unverified'
      AND site.source_type = 'workday'
      AND site.site_url ~* 'myworkdayjobs\.com/.*/job/'
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
        source_type = 'workday',
        source_key = NULLIF(split_part(regexp_replace(detail.board_url, '^https?://[^/]+/', ''), '/', 1), ''),
        review_notes = concat_ws(
            '; ',
            site.review_notes,
            'Canonicalized Workday job-detail URL to parent board (p2-p3-remainder-v1)'
        ),
        updated_at = now()
    FROM detail
    WHERE site.site_id = detail.site_id
      AND detail.keep_rank = 1
      AND detail.board_url ~* '^https?://[^/]+\.myworkdayjobs\.com/[^/]+$'
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
    reviewed_by = 'system:reject-workday-job-detail-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Rejected Workday job-detail URL; parent board already present or could not canonicalize'
    ),
    updated_at = now()
FROM detail
WHERE site.site_id = detail.site_id
  AND NOT EXISTS (SELECT 1 FROM updated WHERE updated.site_id = site.site_id);

-- ---------------------------------------------------------------------------
-- 2) Reject Amazon single-job pages (not company boards).
-- ---------------------------------------------------------------------------
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-amazon-job-detail-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Rejected Amazon job-detail URL; need an Amazon Jobs search/board URL instead'
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.verification_status = 'unverified'
  AND site.source_type = 'amazon_jobs'
  AND site.site_url ~* 'amazon\.jobs/.*/jobs/[0-9]+/'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'nicole%'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'manual%'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  );

-- ---------------------------------------------------------------------------
-- 3) Normalize UltiPro JobBoard → ListJobs when path is recoverable.
-- ---------------------------------------------------------------------------
UPDATE jobpush.career_sites site
SET site_url = regexp_replace(
        site.site_url,
        '^(https?://recruiting\.ultipro\.com/[^/]+/JobBoard)(?:/[0-9a-f-]{36})?.*$',
        '\1/ListJobs',
        'i'
    ),
    source_key = regexp_replace(
        regexp_replace(site.site_url, '^https?://recruiting\.ultipro\.com/', '', 'i'),
        '(?i)/JobBoard(?:/[0-9a-f-]{36})?.*$',
        '/JobBoard/ListJobs'
    ),
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Normalized UltiPro board URL to ListJobs (p2-p3-remainder-v1)'
    ),
    updated_at = now()
WHERE site.source_type = 'ultipro'
  AND site.normalized_domain = 'recruiting.ultipro.com'
  AND site.verification_status = 'unverified'
  AND site.site_url ~* '^https?://recruiting\.ultipro\.com/[^/]+/JobBoard'
  AND site.site_url !~* '/JobBoard/ListJobs$';

-- Reject UltiPro URLs that still are not ListJobs boards.
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-bad-ultipro-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Rejected UltiPro URL that is not a JobBoard/ListJobs entrypoint'
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.verification_status = 'unverified'
  AND site.source_type = 'ultipro'
  AND site.site_url !~* '/jobboard/listjobs$'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'nicole%'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'manual%'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  );

-- ---------------------------------------------------------------------------
-- 4) Auto-trust best remaining supported structured boards (same gates as v5).
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
      AND NOT (
          site.source_type = 'workday'
          AND site.site_url ~* 'myworkdayjobs\.com/.*/job/'
      )
      AND NOT (
          site.source_type = 'amazon_jobs'
          AND site.site_url ~* 'amazon\.jobs/.*/jobs/[0-9]+/'
      )
      AND (
          site.source_type IN ('amazon_jobs', 'greenhouse', 'workday', 'lever', 'ashby', 'smartrecruiters', 'oracle_cloud')
          OR (site.source_type = 'workable' AND site.normalized_domain = 'apply.workable.com')
          OR (site.source_type = 'jobvite' AND site.normalized_domain = 'jobs.jobvite.com')
          OR (site.source_type = 'paylocity' AND site.normalized_domain = 'recruiting.paylocity.com')
          OR (site.source_type = 'rippling' AND site.normalized_domain = 'ats.rippling.com')
          OR (site.source_type = 'applytojob' AND site.normalized_domain LIKE '%.applytojob.com')
          OR (site.source_type = 'catsone' AND site.normalized_domain LIKE '%.catsone.com')
          OR (site.source_type = 'trakstar' AND site.normalized_domain LIKE '%.hire.trakstar.com')
          OR (site.source_type = 'breezy' AND site.normalized_domain LIKE '%.breezy.hr')
          OR (site.source_type = 'dover' AND site.normalized_domain = 'app.dover.com')
          OR (
              site.source_type = 'icims'
              AND site.normalized_domain LIKE '%.icims.com'
              AND site.normalized_domain <> 'icims.com'
              AND site.site_url !~* '(icims\.com/legal|/privacy|/jobs/login$|internal[-.])'
              AND NOT (
                  site.consecutive_failures >= 2
                  AND (
                      coalesce(site.last_error, '') ILIKE '%timeout%'
                      OR coalesce(site.last_error, '') ILIKE '%timed out%'
                  )
              )
          )
          OR (
              site.source_type = 'ultipro'
              AND site.normalized_domain = 'recruiting.ultipro.com'
              AND site.site_url ~* '/jobboard/listjobs$'
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
        'Auto-trusted after P2/P3 remainder canonicalize/normalize wave'
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
);

UPDATE jobpush.career_sites site
SET crawl_interval_hours = CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
        WHEN 'P3' THEN 336
    END,
    next_crawl_at = COALESCE(site.next_crawl_at, now()),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.reviewed_by = 'system:structured-ats-best-v5'
  AND site.review_notes LIKE '%P2/P3 remainder canonicalize/normalize wave%';

-- ---------------------------------------------------------------------------
-- 5) Retry failed first crawls for newly promoted generic JSON-LD sites.
-- ---------------------------------------------------------------------------
UPDATE jobpush.career_sites site
SET crawl_status = 'pending',
    next_crawl_at = now(),
    last_error = NULL,
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.reviewed_by = 'system:generic-jsonld-v1'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed';

COMMIT;

\echo '=== Newly auto-trusted this wave (by source) ==='
SELECT source_type, count(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_by = 'system:structured-ats-best-v5'
  AND review_notes LIKE '%P2/P3 remainder canonicalize/normalize wave%'
GROUP BY 1
ORDER BY sites DESC;

\echo '=== Workday canonicalize outcomes ==='
SELECT
    CASE
        WHEN verification_status = 'verified' AND site_url !~* '/job/' THEN 'board_enabled'
        WHEN verification_status = 'unverified' AND site_url !~* '/job/' THEN 'board_pending'
        WHEN verification_status = 'rejected' THEN 'detail_rejected'
        ELSE 'other'
    END AS outcome,
    count(*) AS sites
FROM jobpush.career_sites
WHERE review_notes ILIKE '%p2-p3-remainder-v1%'
   OR reviewed_by IN ('system:reject-workday-job-detail-v1', 'system:reject-amazon-job-detail-v1')
GROUP BY 1
ORDER BY sites DESC;

\echo '=== Retried generic-jsonld failures now pending ==='
SELECT target.priority_tier, count(*) AS pending_retries
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:generic-jsonld-v1'
  AND target.priority_tier IN ('P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'pending'
  AND site.last_success_at IS NULL
GROUP BY 1
ORDER BY 1;

\echo '=== Remaining structured unverified rank-1 (no enabled site) ==='
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
