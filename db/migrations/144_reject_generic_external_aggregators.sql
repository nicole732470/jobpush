BEGIN;

-- The 2026-07-07 generic template audit showed these domains recurring as
-- external job boards, school/industry boards, visa/job aggregators, or
-- portfolio listings. They are not employer-owned career sites, so do not
-- spend generic-parser or review time on them.
INSERT INTO jobpush.career_site_discovery_domain_excludes (domain, reason, active)
VALUES
    ('internshala.com', 'external internship/job board; not employer-owned career site', TRUE),
    ('localjobs.sulekha.com', 'external local job board; not employer-owned career site', TRUE),
    ('johngannonblog.com', 'external finance/VC job board; not employer-owned career site', TRUE),
    ('jobs.chronicle.com', 'external education job board; not employer-owned career site', TRUE),
    ('us.fashionjobs.com', 'external fashion job board; not employer-owned career site', TRUE),
    ('capd.mit.edu', 'school career center job board; not employer-owned career site', TRUE),
    ('climatechangecareers.com', 'external climate job board; not employer-owned career site', TRUE),
    ('entertainmentcareers.net', 'external entertainment job board; not employer-owned career site', TRUE),
    ('au.seek.com', 'non-US external job board; not employer-owned career site', TRUE),
    ('gulftalent.com', 'external/non-US job board; not employer-owned career site', TRUE),
    ('employer.practicematch.com', 'external healthcare job board; not employer-owned career site', TRUE),
    ('migratemate.co', 'visa/job content aggregator; not employer-owned career site', TRUE),
    ('usnlx.com', 'external job board; not employer-owned career site', TRUE),
    ('jobs-redefined.co', 'external job board; not employer-owned career site', TRUE)
ON CONFLICT (domain) DO UPDATE SET
    reason = EXCLUDED.reason,
    active = TRUE;

UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    reviewed_by = 'system:generic-external-aggregator-cleanup-v1',
    reviewed_at = now(),
    last_error = 'rejected_external_aggregator_generic_candidate',
    review_notes = concat_ws('; ', site.review_notes, excluded.reason),
    updated_at = now()
FROM jobpush.career_site_discovery_domain_excludes excluded
WHERE site.verification_status = 'unverified'
  AND site.source_type = 'generic_html'
  AND excluded.active
  AND (
      site.normalized_domain = excluded.domain
      OR site.normalized_domain LIKE '%.' || excluded.domain
  );

-- Some H1B/visa pages live on otherwise ambiguous domains; reject by path,
-- not whole domain, to avoid blocking legitimate companies with common names.
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    reviewed_by = 'system:generic-external-aggregator-cleanup-v1',
    reviewed_at = now(),
    last_error = 'rejected_external_aggregator_generic_candidate',
    review_notes = concat_ws('; ', site.review_notes, 'Rejected visa-sponsor/content page; not employer-owned career site'),
    updated_at = now()
WHERE site.verification_status = 'unverified'
  AND site.source_type = 'generic_html'
  AND site.site_url ~* '/(visa-sponsors?|companies-that-sponsor|h1b-sponsors?|cloud-consultant-jobs)/';

COMMIT;

SELECT reviewed_by, normalized_domain, count(*) AS rejected_sites
FROM jobpush.career_sites
WHERE reviewed_by = 'system:generic-external-aggregator-cleanup-v1'
GROUP BY reviewed_by, normalized_domain
ORDER BY rejected_sites DESC, normalized_domain
LIMIT 50;

