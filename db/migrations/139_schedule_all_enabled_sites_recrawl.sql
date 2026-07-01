BEGIN;

UPDATE jobpush.career_sites site
SET crawl_status = 'pending',
    next_crawl_at = now(),
    consecutive_failures = 0,
    last_error = NULL,
    review_notes = concat_ws('; ', site.review_notes, 'Scheduled full recrawl with latest crawl/title rules (2026-06-30).'),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown';

COMMIT;

\pset pager off

SELECT priority_tier, source_type, count(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT count(*) AS total_due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due;
