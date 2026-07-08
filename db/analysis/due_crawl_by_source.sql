\pset pager off

SELECT
    priority_tier,
    source_type,
    count(*) AS due_sites,
    count(*) FILTER (WHERE crawl_status = 'failed') AS failed_now,
    min(priority_score) AS min_priority_score,
    max(priority_score) AS max_priority_score
FROM jobpush.crawl_schedule_queue
WHERE is_due
  AND crawl_status <> 'running'
GROUP BY 1, 2
ORDER BY
    CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 9 END,
    due_sites DESC,
    source_type;
