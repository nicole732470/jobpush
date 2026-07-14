\pset pager off

SELECT priority_tier, count(*) AS due_sites_before
FROM jobpush.crawl_schedule_queue
WHERE is_due AND crawl_status <> 'running'
GROUP BY priority_tier
ORDER BY priority_tier;

BEGIN;

UPDATE jobpush.career_sites site
SET crawl_interval_hours = CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 48
        WHEN 'P2' THEN 96
        WHEN 'P3' THEN 168
    END,
    next_crawl_at = CASE
        WHEN site.last_success_at IS NOT NULL THEN
            site.last_success_at + make_interval(hours => CASE target.priority_tier
                WHEN 'P0' THEN 24
                WHEN 'P1' THEN 48
                WHEN 'P2' THEN 96
                WHEN 'P3' THEN 168
            END)
        WHEN site.crawl_status = 'failed' THEN site.next_crawl_at
        ELSE now()
    END,
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled;

COMMIT;

SELECT priority_tier,
       min(crawl_interval_hours) AS interval_hours,
       count(*) AS crawlable_sites,
       count(*) FILTER (WHERE is_due AND crawl_status <> 'running') AS due_sites_now,
       max(last_success_at) AS latest_success_at
FROM jobpush.crawl_schedule_queue
GROUP BY priority_tier
ORDER BY priority_tier;
