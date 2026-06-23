-- Move Ulta career-site rows onto merged consolidation_key after crawl_targets sync.
BEGIN;

UPDATE jobpush.career_sites
SET consolidation_key = 'ulta',
    updated_at = now()
WHERE consolidation_key IN ('46-1142752', '36-4832212');

WITH ranked AS (
    SELECT
        site.site_id,
        ROW_NUMBER() OVER (
            ORDER BY
                CASE site.verification_status WHEN 'verified' THEN 0 ELSE 1 END,
                site.candidate_score DESC NULLS LAST,
                site.site_id
        ) AS new_rank
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = 'ulta'
)
UPDATE jobpush.career_sites site
SET candidate_rank = ranked.new_rank,
    updated_at = now()
FROM ranked
WHERE site.site_id = ranked.site_id;

UPDATE jobpush.crawl_targets
SET
    discovery_status = 'review_pending',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = 'ulta';

UPDATE jobpush.crawl_targets
SET
    enabled = FALSE,
    discovery_status = 'not_found',
    next_discovery_at = now() + INTERVAL '30 days',
    updated_at = now()
WHERE consolidation_key IN ('46-1142752', '36-4832212');

UPDATE jobpush.crawl_priority_overrides
SET consolidation_key = 'ulta',
    updated_at = now()
WHERE consolidation_key IN ('46-1142752', '36-4832212')
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.crawl_priority_overrides existing
      WHERE existing.consolidation_key = 'ulta'
        AND existing.active
  );

DELETE FROM jobpush.crawl_priority_overrides
WHERE consolidation_key IN ('46-1142752', '36-4832212')
  AND EXISTS (
      SELECT 1
      FROM jobpush.crawl_priority_overrides existing
      WHERE existing.consolidation_key = 'ulta'
        AND existing.active
  );

COMMIT;
