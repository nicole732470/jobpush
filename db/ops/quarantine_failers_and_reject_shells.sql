\pset pager off

-- A) Quarantine chronic never-succeeded auto-trust boards + normalize obvious bad URLs
-- C) Keep Comeet slug-only / Brassring shells rejected; Comeet UID boards become auto-trustable

BEGIN;

-- Prefer existing boards.greenhouse.io rows over http/job-boards duplicates.
-- Avoid rewriting site_url in bulk (unique constraint collisions across siblings).
UPDATE jobpush.career_sites site
SET crawl_enabled = FALSE,
    crawl_status = 'paused',
    verification_status = 'rejected',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-greenhouse-duplicate-host-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Rejected Greenhouse http/job-boards duplicate; preferred boards.greenhouse.io sibling'
    ),
    updated_at = now()
WHERE site.source_type = 'greenhouse'
  AND (
      site.site_url ~* '^http://'
      OR site.site_url ~* 'job-boards\.greenhouse\.io'
  )
  AND EXISTS (
      SELECT 1
      FROM jobpush.career_sites sibling
      WHERE sibling.consolidation_key = site.consolidation_key
        AND sibling.site_id <> site.site_id
        AND sibling.verification_status = 'verified'
        AND sibling.crawl_enabled
        AND sibling.site_url ~* 'boards\.greenhouse\.io'
        AND regexp_replace(lower(sibling.site_url), '/+$', '')
          = regexp_replace(
                lower(
                    regexp_replace(
                        regexp_replace(site.site_url, '^http://', 'https://', 'i'),
                        'job-boards\.greenhouse\.io',
                        'boards.greenhouse.io',
                        'i'
                    )
                ),
                '/+$',
                ''
            )
  );

-- Quarantine never-succeeded auto-trust sites with repeated failures.
UPDATE jobpush.career_sites site
SET crawl_enabled = FALSE,
    crawl_status = 'paused',
    verification_status = 'unverified',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:quarantine-never-succeeded-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Quarantined never-succeeded auto-trust board after repeated crawl failures'
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.last_success_at IS NULL
  AND site.consecutive_failures >= 3
  AND COALESCE(site.reviewed_by, '') LIKE 'system:%';

-- Quarantine Rippling locale shells that are not company tenant boards.
UPDATE jobpush.career_sites site
SET crawl_enabled = FALSE,
    crawl_status = 'paused',
    verification_status = 'unverified',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:quarantine-rippling-locale-shell-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Quarantined Rippling locale shell (/xx-YY/jobs) without company tenant slug'
    ),
    updated_at = now()
WHERE site.source_type = 'rippling'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.site_url ~* 'ats\.rippling\.com/[a-z]{2}-[A-Z]{2}/jobs/?$'
  AND site.last_success_at IS NULL;

-- Reopen Comeet UID boards / Brassring tenant boards previously rejected as no-parser.
UPDATE jobpush.career_sites site
SET verification_status = 'unverified',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reopen-comeet-brassring-parser-ready-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Reopened for Comeet/Brassring parser; good URL shape'
    ),
    updated_at = now()
WHERE site.source_type IN ('comeet', 'brassring')
  AND site.verification_status = 'rejected'
  AND COALESCE(site.reviewed_by, '') LIKE 'system:reject-no-parser%'
  AND (
      (
          site.source_type = 'comeet'
          AND site.site_url ~* 'comeet\.(com|co)/jobs/[^/]+/[0-9A-Fa-f]+\.[0-9A-Fa-f]+'
      )
      OR (
          site.source_type = 'brassring'
          AND site.site_url ~* 'partnerid='
          AND site.site_url ~* 'siteid='
      )
  );

-- Reject remaining Comeet slug-only shells (API needs /jobs/{slug}/{UID}).
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-comeet-slug-shell-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Rejected Comeet slug-only URL; need hosted board /jobs/{slug}/{COMPANY.UID}'
    ),
    updated_at = now()
WHERE site.source_type = 'comeet'
  AND site.verification_status IN ('unverified', 'rejected')
  AND site.site_url ~* 'comeet\.(com|co)/jobs/[^/?#]+/?$'
  AND site.site_url !~* 'comeet\.(com|co)/jobs/[^/]+/[0-9A-Fa-f]+\.[0-9A-Fa-f]+'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'nicole%'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'manual%';

-- Reject Brassring shells still lacking partnerid+siteid.
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-brassring-shell-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Rejected Brassring shell; need partnerid+siteid tenant board URL'
    ),
    updated_at = now()
WHERE site.source_type = 'brassring'
  AND site.verification_status IN ('unverified', 'rejected')
  AND (
      site.site_url !~* 'partnerid='
      OR site.site_url !~* 'siteid='
  )
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'nicole%'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'manual%';

COMMIT;

SELECT reviewed_by, count(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_by IN (
    'system:reject-greenhouse-duplicate-host-v1',
    'system:quarantine-never-succeeded-v1',
    'system:quarantine-rippling-locale-shell-v1',
    'system:reopen-comeet-brassring-parser-ready-v1',
    'system:reject-comeet-slug-shell-v1',
    'system:reject-brassring-shell-v1'
)
  AND reviewed_at >= now() - interval '10 minutes'
GROUP BY 1
ORDER BY 1;
