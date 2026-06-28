\pset pager off

BEGIN;

-- ponytail: denylist only domains already observed as repeated third-party
-- job boards/noisy pages; add domains here only after blocker audit confirms.
WITH noisy(host, reason) AS (
    VALUES
        ('climatechangecareers.com', 'third-party climate job board'),
        ('internshala.com', 'third-party internship/job board'),
        ('jobdirectly.com', 'third-party job board'),
        ('jobs.tampabay.com', 'third-party job board'),
        ('jobs.alanet.org', 'third-party association job board')
), matched AS (
    SELECT site.site_id, noisy.reason
    FROM jobpush.career_sites site
    JOIN noisy
      ON lower(regexp_replace(coalesce(site.normalized_domain, split_part(regexp_replace(site.site_url, '^https?://', ''), '/', 1)), '^www\.', '')) = noisy.host
    WHERE site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
)
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'pending',
    review_notes = concat_ws('; ', site.review_notes, 'Rejected by 097 generic third-party cleanup: ' || matched.reason),
    reviewed_by = 'system:generic-third-party-cleanup-v1',
    reviewed_at = now(),
    updated_at = now()
FROM matched
WHERE site.site_id = matched.site_id;

COMMIT;

SELECT reviewed_by, verification_status, count(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_by = 'system:generic-third-party-cleanup-v1'
GROUP BY 1, 2
ORDER BY 1, 2;
