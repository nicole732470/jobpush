BEGIN;

-- Clean up generic_html candidates discovered after migration 074.
-- Many high-score "generic" rows are external job boards / VC portfolio boards,
-- not employer-owned career sites. Others are structured ATS URLs that should
-- be routed to existing adapters.

INSERT INTO jobpush.career_site_discovery_domain_excludes (domain, reason, active)
VALUES
    ('themuse.com', 'external job/company profile board; not employer-owned career site', TRUE),
    ('whatjobs.com', 'external job board; not employer-owned career site', TRUE),
    ('bandana.com', 'external company/job board; not employer-owned career site', TRUE),
    ('powderkeg.com', 'external startup/job board; not employer-owned career site', TRUE),
    ('frontendnode-production.up.railway.app', 'external mirrored job board; not employer-owned career site', TRUE),
    ('web3.career', 'external job board; not employer-owned career site', TRUE),
    ('jobleads.com', 'external job board; not employer-owned career site', TRUE),
    ('4dayweek.io', 'external job/company board; not employer-owned career site', TRUE),
    ('simplify.jobs', 'external job board; not employer-owned career site', TRUE),
    ('ehscareers.com', 'external industry job board; not employer-owned career site', TRUE),
    ('glassdoor.sg', 'external job board; not employer-owned career site', TRUE),
    ('linemancentral.com', 'external industry job board; not employer-owned career site', TRUE),
    ('career.io', 'external job/career service; not employer-owned career site', TRUE),
    ('healthecareers.com', 'external healthcare job board; not employer-owned career site', TRUE),
    ('careers.usnews.com', 'external ranking/content site; not employer-owned career site', TRUE),
    ('salesjobs.com', 'external sales job board; not employer-owned career site', TRUE),
    ('remote.com', 'external job board / EOR platform; not employer-owned career site for listed company', TRUE),
    ('wallstreetcareers.com', 'external job board; not employer-owned career site', TRUE),
    ('energyjobshop.com', 'external industry job board; not employer-owned career site', TRUE),
    ('scoutify.com', 'external company/job board; not employer-owned career site', TRUE),
    ('talent.com', 'external job board; not employer-owned career site', TRUE),
    ('dailyremote.com', 'external remote job board; not employer-owned career site', TRUE),
    ('foundit.in', 'external job board; not employer-owned career site', TRUE),
    ('unstop.com', 'external job/company board; not employer-owned career site', TRUE),
    ('trueup.io', 'external job board; not employer-owned career site', TRUE),
    ('app.careerpuck.com', 'external job board; not employer-owned career site', TRUE),
    ('careers-page.com', 'third-party career-page host; not automatically employer-owned without verification', TRUE),
    ('jobs.gem.com', 'third-party / portfolio job board; not employer-owned career site', TRUE),
    ('ev.careers', 'third-party / portfolio career board; not employer-owned career site', TRUE),
    ('careerhub.biocom.org', 'association job board; not employer-owned career site', TRUE),
    ('jobs.paypal.vc', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('careers.ivp.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.abstractvc.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.insightpartners.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.linkventures.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.startx.com', 'accelerator portfolio job board; not employer-owned career site', TRUE),
    ('careers.playground.global', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.nextview.vc', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.foothill.ventures', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('careers.celesta.vc', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('careers.innospark.vc', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.kleinerperkins.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('careers.peakxv.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('jobs.forerunnerventures.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('careers.sorensoncap.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('careers.aixventures.com', 'VC portfolio job board; not employer-owned career site', TRUE),
    ('careers.nvp.com', 'VC portfolio job board; not employer-owned career site', TRUE)
ON CONFLICT (domain) DO UPDATE SET
    reason = EXCLUDED.reason,
    active = TRUE;

UPDATE jobpush.career_sites site
SET
    verification_status = 'rejected',
    crawl_enabled = FALSE,
    reviewed_by = 'system:generic-html-cleanup-v2',
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
    source_key = CASE
        WHEN split_part(regexp_replace(site_url, '^https?://jobs\.jobvite\.com/', ''), '/', 1) = 'careers'
            THEN split_part(regexp_replace(site_url, '^https?://jobs\.jobvite\.com/', ''), '/', 2)
        ELSE split_part(regexp_replace(site_url, '^https?://jobs\.jobvite\.com/', ''), '/', 1)
    END,
    site_kind = 'ats_feed',
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, 'Reclassified from generic_html by 086')
WHERE source_type = 'generic_html'
  AND normalized_domain = 'jobs.jobvite.com';

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
