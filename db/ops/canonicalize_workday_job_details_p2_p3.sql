\pset pager off

-- Promote Workday /job/... detail URLs to parent boards, then auto-trust.
-- Accepts optional locale path segment (e.g. /en-US/BoardName).

BEGIN;

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
), board_ok AS (
    SELECT *
    FROM detail
    WHERE board_url ~* '^https?://[^/]+\.myworkdayjobs\.com/(?:[a-z]{2}-[A-Z]{2}/)?[^/?#]+$'
), updated AS (
    UPDATE jobpush.career_sites site
    SET site_url = board_ok.board_url,
        site_kind = 'ats_feed',
        source_type = 'workday',
        source_key = NULLIF(
            CASE
                WHEN regexp_replace(board_ok.board_url, '^https?://[^/]+/', '') ~ '^[a-z]{2}-[A-Z]{2}/'
                THEN split_part(
                    regexp_replace(board_ok.board_url, '^https?://[^/]+/[a-z]{2}-[A-Z]{2}/', ''),
                    '/',
                    1
                )
                ELSE split_part(
                    regexp_replace(board_ok.board_url, '^https?://[^/]+/', ''),
                    '/',
                    1
                )
            END,
            ''
        ),
        review_notes = concat_ws(
            '; ',
            site.review_notes,
            'Canonicalized Workday job-detail URL to parent board (workday-board-v2)'
        ),
        updated_at = now()
    FROM board_ok
    WHERE site.site_id = board_ok.site_id
      AND board_ok.keep_rank = 1
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites existing
          WHERE existing.consolidation_key = site.consolidation_key
            AND existing.site_url = board_ok.board_url
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

COMMIT;

SELECT
    count(*) FILTER (
        WHERE verification_status = 'unverified'
          AND site_url !~* '/job/'
          AND coalesce(review_notes, '') ILIKE '%workday-board-v2%'
    ) AS boards_ready,
    count(*) FILTER (
        WHERE reviewed_by = 'system:reject-workday-job-detail-v1'
          AND reviewed_at >= now() - interval '5 minutes'
    ) AS details_rejected_recently
FROM jobpush.career_sites
WHERE source_type = 'workday';
