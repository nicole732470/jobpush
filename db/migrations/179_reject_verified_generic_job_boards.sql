BEGIN;

-- Confirmed in the 2026-07-13/14 failure cohort. These are association or
-- government job boards that host postings for many unrelated employers;
-- they are not the selected company's official careers site.
INSERT INTO jobpush.career_site_discovery_domain_excludes(domain, reason, active)
VALUES
  ('careers.asq.org', 'ASQ association job board; not employer-owned careers site', TRUE),
  ('careers.computer.org', 'IEEE Computer Society association job board; not employer-owned careers site', TRUE),
  ('illinoisjoblink.illinois.gov', 'Illinois government job board; not employer-owned careers site', TRUE),
  ('lgbtgreatcareers.com', 'external multi-employer job board; not employer-owned careers site', TRUE)
ON CONFLICT(domain) DO UPDATE SET reason=EXCLUDED.reason,active=TRUE;

UPDATE jobpush.career_sites site
SET verification_status='rejected',crawl_enabled=FALSE,crawl_status='paused',
    next_crawl_at=NULL,reviewed_by='system:generic-job-board-cleanup-v3',
    reviewed_at=now(),last_error='rejected_external_job_board_not_company_site',
    review_notes=concat_ws('; ',site.review_notes,excluded.reason),updated_at=now()
FROM jobpush.career_site_discovery_domain_excludes excluded
WHERE site.source_type='generic_html'
  AND excluded.domain IN (
    'careers.asq.org','careers.computer.org',
    'illinoisjoblink.illinois.gov','lgbtgreatcareers.com'
  )
  AND (site.normalized_domain=excluded.domain OR site.normalized_domain LIKE '%.' || excluded.domain)
  AND (site.verification_status<>'rejected' OR site.crawl_enabled);

COMMIT;

SELECT normalized_domain,count(*) AS rejected_sites
FROM jobpush.career_sites
WHERE reviewed_by='system:generic-job-board-cleanup-v3'
GROUP BY normalized_domain ORDER BY rejected_sites DESC,normalized_domain;
