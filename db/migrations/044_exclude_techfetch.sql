BEGIN;

INSERT INTO jobpush.career_site_discovery_domain_excludes (domain, reason, active)
VALUES ('techfetch.com', 'external IT job aggregator; not an employer career site', TRUE)
ON CONFLICT (domain) DO UPDATE SET
    reason = EXCLUDED.reason,
    active = TRUE;

SELECT jobpush.review_career_site(
    226,
    'rejected',
    'nicole',
    'TechFetch is an external IT job aggregator, not the official site for IT Soft USA, Inc.'
);

COMMIT;
