\pset pager off

BEGIN;

-- Reject obvious non-board structured candidates still sitting in review.
-- Only touches unverified, not-yet-enabled rows; human labels stay authoritative.
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-bad-unverified-structured-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        CASE
            WHEN site.source_type = 'workday'
                AND site.site_url ~* 'myworkdayjobs\.com/.*/job/'
                THEN 'Rejected Workday job-detail URL; need parent board URL'
            WHEN site.source_type = 'workable'
                AND site.site_url ~* 'jobs\.workable\.com/(company|view)'
                THEN 'Rejected generic Workable landing page; need company board URL'
            WHEN site.source_type = 'icims'
                AND site.normalized_domain = 'icims.com'
                THEN 'Rejected iCIMS vendor root/legal page'
            WHEN site.source_type = 'icims'
                AND site.site_url ~* '(icims\.com/legal|/privacy|/jobs/login$|internal[-.])'
                THEN 'Rejected iCIMS login/internal/privacy URL'
            ELSE 'Rejected bad structured candidate'
        END
    ),
    updated_at = now()
WHERE site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'nicole%'
  AND COALESCE(site.reviewed_by, '') NOT LIKE 'manual%'
  AND (
      (site.source_type = 'workday' AND site.site_url ~* 'myworkdayjobs\.com/.*/job/')
      OR (site.source_type = 'workable' AND site.site_url ~* 'jobs\.workable\.com/(company|view)')
      OR (site.source_type = 'icims' AND site.normalized_domain = 'icims.com')
      OR (
          site.source_type = 'icims'
          AND site.site_url ~* '(icims\.com/legal|/privacy|/jobs/login$|internal[-.])'
      )
  );

UPDATE jobpush.crawl_targets target
SET discovery_status = 'review_pending',
    updated_at = now()
WHERE target.discovery_status = 'found'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.verification_status = 'verified'
        AND site.crawl_enabled
  )
  AND EXISTS (
      SELECT 1
      FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.reviewed_by = 'system:reject-bad-unverified-structured-v1'
  );

COMMIT;

\echo '=== Rejected by reason ==='
SELECT
    source_type,
    CASE
        WHEN review_notes LIKE '%job-detail%' THEN 'workday_job_detail'
        WHEN review_notes LIKE '%Workable landing%' THEN 'workable_generic_landing'
        WHEN review_notes LIKE '%vendor root%' THEN 'icims_vendor_root'
        WHEN review_notes LIKE '%login/internal%' THEN 'icims_login_internal'
        ELSE 'other'
    END AS reason,
    count(*) AS sites,
    count(DISTINCT consolidation_key) AS companies
FROM jobpush.career_sites
WHERE reviewed_by = 'system:reject-bad-unverified-structured-v1'
GROUP BY 1, 2
ORDER BY companies DESC, source_type, reason;

\echo '=== P2 structured still waiting (post-cleanup) ==='
SELECT site.source_type, count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled AND target.priority_tier = 'P2'
  AND site.verification_status = 'unverified'
  AND site.source_type <> 'generic_html'
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
GROUP BY site.source_type
ORDER BY companies DESC;
