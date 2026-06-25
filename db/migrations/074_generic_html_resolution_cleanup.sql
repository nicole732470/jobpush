BEGIN;

INSERT INTO jobpush.career_site_discovery_domain_excludes (domain, reason, active)
VALUES
    ('wellfound.com', 'external job/company aggregator; not employer-owned career site', TRUE),
    ('bebee.com', 'external job/company aggregator; not employer-owned career site', TRUE),
    ('zippia.com', 'external job/company aggregator; not employer-owned career site', TRUE),
    ('uplers.com', 'external talent/job aggregator; not employer-owned career site', TRUE),
    ('builtinsf.com', 'external Built In job board; not employer-owned career site', TRUE),
    ('builtinboston.com', 'external Built In job board; not employer-owned career site', TRUE),
    ('builtinla.com', 'external Built In job board; not employer-owned career site', TRUE),
    ('builtinaustin.com', 'external Built In job board; not employer-owned career site', TRUE),
    ('builtinseattle.com', 'external Built In job board; not employer-owned career site', TRUE),
    ('builtincolorado.com', 'external Built In job board; not employer-owned career site', TRUE),
    ('consider.com', 'external portfolio/job board; not employer-owned career site', TRUE),
    ('jobaaj.com', 'external job board; not employer-owned career site', TRUE),
    ('startup.jobs', 'external job board; not employer-owned career site', TRUE),
    ('welcometothejungle.com', 'external job board; not employer-owned career site', TRUE),
    ('app.welcometothejungle.com', 'external job board; not employer-owned career site', TRUE),
    ('lensa.com', 'external job board; not employer-owned career site', TRUE),
    ('myvisajobs.com', 'external visa/job data site; not employer-owned career site', TRUE),
    ('iitjobs.com', 'external job board; not employer-owned career site', TRUE),
    ('iimjobs.com', 'external job board; not employer-owned career site', TRUE),
    ('eujobs.co', 'external job/career-guide site; not employer-owned career site', TRUE),
    ('optnation.com', 'external job board; not employer-owned career site', TRUE),
    ('glassdoor.co.in', 'external job board; not employer-owned career site', TRUE),
    ('glassdoor.ie', 'external job board; not employer-owned career site', TRUE),
    ('mediabistro.com', 'external job board; not employer-owned career site', TRUE),
    ('remotejobs.org', 'external job board; not employer-owned career site', TRUE),
    ('terra.do', 'external job board; not employer-owned career site', TRUE),
    ('sorce.jobs', 'external job board; not employer-owned career site', TRUE),
    ('ycombinator.com', 'external accelerator/portfolio job board; not employer-owned career site', TRUE),
    ('clearancejobs.com', 'external job board; not employer-owned career site', TRUE),
    ('reddit.com', 'social/forum result; not employer-owned career site', TRUE),
    ('hirist.tech', 'external job board; not employer-owned career site', TRUE),
    ('tealhq.com', 'external job board; not employer-owned career site', TRUE),
    ('jobzmall.com', 'external job board; not employer-owned career site', TRUE),
    ('showbizjobs.com', 'external job board; not employer-owned career site', TRUE),
    ('torre.ai', 'external job board; not employer-owned career site', TRUE),
    ('ambitionbox.com', 'external company/job board; not employer-owned career site', TRUE),
    ('snagajob.com', 'external job board; not employer-owned career site', TRUE),
    ('grad.jobs', 'external job board; not employer-owned career site', TRUE),
    ('careers.diversityworking.com', 'external diversity job board; not employer-owned career site', TRUE),
    ('dreamhire.io', 'external job board; not employer-owned career site', TRUE),
    ('efinancialcareers.com', 'external job board; not employer-owned career site', TRUE),
    ('myjobsny.usnlx.com', 'external national labor exchange mirror; not employer-owned career site', TRUE),
    ('jobgether.com', 'external job board; not employer-owned career site', TRUE),
    ('governmentjobs.com', 'external government job board; not employer-owned private-company site', TRUE),
    ('dynamitejobs.com', 'external job board; not employer-owned career site', TRUE),
    ('weworkremotely.com', 'external job board; not employer-owned career site', TRUE),
    ('devitjobs.com', 'external job board; not employer-owned career site', TRUE),
    ('careersingovernment.com', 'external job board; not employer-owned career site', TRUE),
    ('himalayas.app', 'external job board; not employer-owned career site', TRUE),
    ('metaintro.com', 'external job/company board; not employer-owned career site', TRUE),
    ('oysterlink.com', 'external job/company board; not employer-owned career site', TRUE),
    ('diversityjobs.com', 'external job board; not employer-owned career site', TRUE),
    ('jobs.a16z.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.sequoiacap.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('careers.capitalg.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.gv.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.battery.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.baincapitalventures.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('careers.nea.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.greylock.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.techaviv.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.gaingels.com', 'portfolio job board; not employer-owned career site', TRUE),
    ('jobs.fin.capital', 'portfolio job board; not employer-owned career site', TRUE),
    ('jobs.bvp.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.lsvp.com', 'VC portfolio job board; not employer-owned career site', TRUE)
ON CONFLICT (domain) DO UPDATE SET
    reason = EXCLUDED.reason,
    active = TRUE;

UPDATE jobpush.career_sites site
SET
    verification_status = 'rejected',
    crawl_enabled = FALSE,
    reviewed_by = 'system:generic-html-cleanup-v1',
    reviewed_at = now(),
    review_notes = excluded.reason,
    updated_at = now()
FROM jobpush.career_site_discovery_domain_excludes excluded
WHERE site.verification_status = 'unverified'
  AND site.source_type = 'generic_html'
  AND excluded.active
  AND (
      site.normalized_domain = excluded.domain
      OR site.normalized_domain LIKE '%.' || excluded.domain
  );

UPDATE jobpush.career_sites
SET
    source_type = 'jobvite',
    source_key = split_part(site_url, '/', 5),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 074')
WHERE source_type = 'generic_html'
  AND normalized_domain = 'jobs.jobvite.com'
  AND site_url LIKE '%/careers/%/jobs%';

UPDATE jobpush.career_sites
SET
    source_type = 'workable',
    source_key = split_part(regexp_replace(site_url, '^https?://[^/]+/', ''), '/', 1),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 074')
WHERE source_type = 'generic_html'
  AND normalized_domain IN ('apply.workable.com', 'jobs.workable.com');

UPDATE jobpush.career_sites
SET
    source_type = 'paylocity',
    source_key = regexp_replace(site_url, '^https?://recruiting\.paylocity\.com/', ''),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 074')
WHERE source_type = 'generic_html'
  AND normalized_domain = 'recruiting.paylocity.com';

UPDATE jobpush.career_sites
SET
    source_type = 'rippling',
    source_key = split_part(regexp_replace(site_url, '^https?://ats\.rippling\.com/', ''), '/', 1),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 074')
WHERE source_type = 'generic_html'
  AND normalized_domain = 'ats.rippling.com';

UPDATE jobpush.career_sites
SET
    source_type = 'ultipro',
    source_key = regexp_replace(site_url, '^https?://recruiting\.ultipro\.com/', ''),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 074')
WHERE source_type = 'generic_html'
  AND normalized_domain = 'recruiting.ultipro.com';

UPDATE jobpush.career_sites
SET
    source_type = 'trinethire',
    source_key = split_part(regexp_replace(site_url, '^https?://app\.trinethire\.com/', ''), '/', 1),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 074')
WHERE source_type = 'generic_html'
  AND normalized_domain = 'app.trinethire.com';

UPDATE jobpush.career_sites
SET
    source_type = 'comeet',
    source_key = regexp_replace(site_url, '^https?://[^/]+/', ''),
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 074')
WHERE source_type = 'generic_html'
  AND normalized_domain LIKE '%.comeet.com';

UPDATE jobpush.crawl_targets target
SET
    discovery_status = CASE
        WHEN EXISTS (
            SELECT 1 FROM jobpush.career_sites site
            WHERE site.consolidation_key = target.consolidation_key
              AND site.verification_status IN ('verified', 'unverified')
        ) THEN target.discovery_status
        ELSE 'not_found'
    END,
    next_discovery_at = CASE
        WHEN EXISTS (
            SELECT 1 FROM jobpush.career_sites site
            WHERE site.consolidation_key = target.consolidation_key
              AND site.verification_status IN ('verified', 'unverified')
        ) THEN target.next_discovery_at
        ELSE now() + INTERVAL '30 days'
    END,
    updated_at = now()
WHERE target.discovery_status = 'review_pending';

COMMIT;
