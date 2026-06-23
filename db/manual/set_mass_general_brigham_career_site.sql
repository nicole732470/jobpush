-- Mass General Brigham career-site fix
-- site_id 32/33/34 as of 2026-06-22

BEGIN;

SELECT jobpush.review_career_site(
    32, 'rejected', 'nicole', 'Wrong career-site candidate'
);

SELECT jobpush.review_career_site(
    33, 'rejected', 'nicole', 'Wrong career-site candidate'
);

SELECT jobpush.review_career_site(
    34, 'rejected', 'nicole', 'Wrong career-site candidate'
);

COMMIT;

-- If you have the correct URL, add + verify in a second transaction:
--
-- BEGIN;
--
-- INSERT INTO jobpush.career_sites (
--     consolidation_key, site_url, normalized_domain,
--     site_kind, source_type, source_key, discovery_source,
--     verification_status, crawl_enabled, crawl_status,
--     evidence_title, review_notes
-- )
-- VALUES (
--     'mass-general-brigham',
--     'https://massgeneralbrigham.wd1.myworkdayjobs.com/MGBExternal',
--     'massgeneralbrigham.wd1.myworkdayjobs.com',
--     'ats_feed', 'workday', 'MGBExternal', 'manual',
--     'unverified', FALSE, 'pending',
--     'Mass General Brigham Workday external careers',
--     'Manual override after Tavily candidates were wrong'
-- )
-- ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
--     source_type = EXCLUDED.source_type,
--     site_kind = EXCLUDED.site_kind,
--     updated_at = now();
--
-- SELECT jobpush.review_career_site(
--     site.site_id, 'verified', 'nicole', 'Official Workday external job board'
-- )
-- FROM jobpush.career_sites site
-- WHERE site.consolidation_key = 'mass-general-brigham'
--   AND site.site_url = 'https://massgeneralbrigham.wd1.myworkdayjobs.com/MGBExternal';
--
-- COMMIT;
