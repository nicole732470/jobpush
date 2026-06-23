BEGIN;

SELECT jobpush.review_career_site(
    126, 'rejected', 'nicole', 'Corporate marketing page; jobs feed already verified at site 125'
);
SELECT jobpush.review_career_site(
    127, 'rejected', 'nicole', 'Wrong career-site candidate'
);
SELECT jobpush.review_career_site(
    128, 'rejected', 'nicole', 'Wrong career-site candidate'
);

UPDATE jobpush.crawl_targets
SET
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = 'ulta';

COMMIT;
