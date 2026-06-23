-- JobPush self-service operations for TablePlus.
-- First find the exact consolidation_key. Never guess it from the company name.
SELECT consolidation_key, canonical_name, crawl_priority_tier
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%PFIZER%';

-- 1) You found the official career site yourself.
-- Safe default: unknown adapter/scope means it is saved and verified, but it
-- will NOT crawl until adapter and US scope are configured.
SELECT jobpush.add_verified_career_site(
    '13-5315170',
    'https://www.pfizer.com/about/careers',
    'unknown',       -- workday / greenhouse / icims / oracle_cloud / apple_jobs / unknown
    NULL,            -- ATS tenant/source key; NULL when unknown
    NULL,            -- use 'US' only when the URL/feed is confirmed US-scoped
    'unknown',       -- server_filter / local_filter / verified_us_only / unknown
    'nicole',
    'Manually confirmed official careers page'
);

-- 2) Manually change a company to P0 (also supports P1 or P2).
SELECT jobpush.set_manual_crawl_priority(
    '13-5315170', 'P0', 'Manual networking priority', 'nicole'
);

-- 3) All three candidates are wrong. Returns how many rows were rejected.
SELECT jobpush.reject_all_career_site_candidates(
    '13-5315170', 'nicole', 'All suggested sites belong to another company or are aggregators'
);

-- 4) One candidate is correct. Copy its candidate_N_site_id from
-- career_site_review_workbench. The other unverified candidates are rejected.
-- Keep country NULL/scope unknown unless you confirmed the site is US-only.
SELECT jobpush.verify_career_site_candidate(
    12345, 'nicole', 'Candidate 1 is the official career site', NULL, 'unknown'
);

-- Verify the resulting company, site, priority, and scheduler state.
SELECT * FROM jobpush.career_site_review_workbench
WHERE consolidation_key = '13-5315170';

SELECT * FROM jobpush.crawl_schedule_queue
WHERE consolidation_key = '13-5315170';
