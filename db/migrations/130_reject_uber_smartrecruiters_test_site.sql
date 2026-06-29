BEGIN;

SELECT jobpush.review_career_site(
    12599,
    'rejected',
    'nicole',
    'SmartRecruiters company slug only returned a stale Test UAT posting; keep Uber on official careers candidates instead.'
);

COMMIT;
