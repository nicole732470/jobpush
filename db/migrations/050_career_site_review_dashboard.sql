BEGIN;

CREATE OR REPLACE VIEW jobpush.career_site_company_review_queue_ranked AS
SELECT
    row_number() OVER (
        ORDER BY CASE queue.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
                 queue.priority_score DESC, queue.canonical_name
    ) AS review_rank,
    (target.priority_source = 'manual_override') AS is_manual_priority,
    queue.*
FROM jobpush.career_site_company_review_queue queue
JOIN jobpush.crawl_targets target USING (consolidation_key)
ORDER BY review_rank;

-- Unlike the pending-only queue, this dashboard deliberately keeps verified
-- companies visible. That makes manual P0 companies such as Google easy to
-- find even after their review has been completed.
CREATE OR REPLACE VIEW jobpush.career_site_company_dashboard AS
WITH site_rollup AS (
    SELECT
        target.consolidation_key,
        count(*) FILTER (WHERE site.verification_status = 'verified') AS verified_site_count,
        count(*) FILTER (WHERE site.verification_status = 'unverified') AS pending_candidate_count,
        count(*) FILTER (WHERE site.verification_status = 'rejected') AS rejected_candidate_count,
        min(site.site_url) FILTER (WHERE site.verification_status = 'verified') AS verified_url,
        min(site.source_type) FILTER (WHERE site.verification_status = 'verified') AS verified_source_type,
        max(site.reviewed_at) FILTER (WHERE site.verification_status = 'verified') AS verified_at
    FROM jobpush.crawl_targets target
    LEFT JOIN jobpush.career_sites site USING (consolidation_key)
    WHERE target.enabled
    GROUP BY target.consolidation_key
)
SELECT
    row_number() OVER (
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
                 CASE target.discovery_status WHEN 'review_pending' THEN 0 WHEN 'found' THEN 1 ELSE 2 END,
                 target.priority_score DESC, target.canonical_name
    ) AS dashboard_rank,
    target.priority_tier,
    (target.priority_source = 'manual_override') AS is_manual_priority,
    target.priority_score,
    target.consolidation_key,
    target.canonical_name,
    target.discovery_status,
    rollup.verified_site_count,
    rollup.pending_candidate_count,
    rollup.rejected_candidate_count,
    rollup.verified_url,
    rollup.verified_source_type,
    rollup.verified_at,
    target.last_discovery_at
FROM jobpush.crawl_targets target
JOIN site_rollup rollup USING (consolidation_key)
WHERE target.enabled
ORDER BY dashboard_rank;

CREATE OR REPLACE VIEW jobpush.career_site_review_precision AS
SELECT
    source_type,
    candidate_rank,
    count(*) FILTER (WHERE reviewed_at IS NOT NULL) AS reviewed_candidates,
    count(*) FILTER (WHERE verification_status = 'verified') AS verified_candidates,
    count(*) FILTER (WHERE verification_status = 'rejected') AS rejected_candidates,
    CASE WHEN count(*) FILTER (WHERE reviewed_at IS NOT NULL) = 0 THEN NULL
         ELSE round(
             count(*) FILTER (WHERE verification_status = 'verified')::numeric
             / count(*) FILTER (WHERE reviewed_at IS NOT NULL), 4
         )
    END AS precision
FROM jobpush.career_sites
WHERE discovery_source = 'tavily_basic'
GROUP BY source_type, candidate_rank;

COMMIT;
