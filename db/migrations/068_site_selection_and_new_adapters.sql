BEGIN;

CREATE OR REPLACE VIEW jobpush.career_site_selection_candidates AS
SELECT
    target.priority_tier,
    target.priority_score,
    target.consolidation_key,
    target.canonical_name,
    site.site_id,
    site.candidate_rank,
    site.site_url,
    site.normalized_domain,
    site.source_type,
    site.verification_status,
    site.crawl_enabled,
    site.target_country_code,
    site.scope_method,
    site.reviewed_by,
    site.last_crawled_at,
    site.last_success_at,
    site.consecutive_failures,
    site.crawl_status,
    (
        CASE WHEN site.verification_status = 'verified' THEN 100 ELSE 0 END
      + CASE WHEN site.source_type IN ('greenhouse','workday','lever','ashby','smartrecruiters','oracle_cloud','apple_jobs') THEN 45 ELSE 0 END
      + CASE WHEN site.source_type = 'icims' THEN 20 ELSE 0 END
      + CASE WHEN site.candidate_rank = 1 THEN 25 WHEN site.candidate_rank = 2 THEN 10 WHEN site.candidate_rank = 3 THEN 5 ELSE 0 END
      + CASE WHEN site.target_country_code = 'US' AND site.scope_method <> 'unknown' THEN 20 ELSE 0 END
      + CASE WHEN site.last_success_at IS NOT NULL THEN 30 ELSE 0 END
      + CASE WHEN site.crawl_status = 'succeeded' THEN 15 ELSE 0 END
      - CASE WHEN site.verification_status = 'rejected' THEN 200 ELSE 0 END
      - CASE WHEN site.consecutive_failures >= 3 THEN 40 ELSE 0 END
      - CASE WHEN site.source_type = 'generic_html' THEN 30 ELSE 0 END
    ) AS selection_score,
    CASE
        WHEN site.verification_status = 'verified' THEN 'selected_verified'
        WHEN site.verification_status = 'rejected' THEN 'rejected'
        WHEN site.source_type IN ('greenhouse','workday','lever','ashby','smartrecruiters')
             AND site.candidate_rank = 1
             AND NOT EXISTS (
                 SELECT 1 FROM jobpush.career_sites verified
                 WHERE verified.consolidation_key = site.consolidation_key
                   AND verified.verification_status = 'verified'
             ) THEN 'auto_trust_rank1_structured_ats'
        WHEN site.source_type IN ('oracle_cloud','apple_jobs')
             AND site.candidate_rank = 1 THEN 'supported_but_needs_specific_review'
        WHEN site.source_type = 'icims' THEN 'needs_icims_us_scope_review'
        WHEN site.source_type = 'generic_html' THEN 'manual_or_later_generic_html'
        ELSE 'review_candidate'
    END AS selection_decision
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled;

WITH eligible AS (
    SELECT site.site_id
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0', 'P1')
      AND site.verification_status = 'unverified'
      AND site.candidate_rank = 1
      AND site.source_type IN ('lever','ashby','smartrecruiters')
      AND NOT EXISTS (
          SELECT 1 FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
      )
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'system:structured-ats-rank1-v2',
    review_notes = 'Auto-trusted rank-1 structured ATS candidate after adapter support was added; monitor crawl health and entity mismatch',
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

UPDATE jobpush.crawl_targets target
SET discovery_status = 'found', next_discovery_at = NULL, updated_at = now()
WHERE EXISTS (
    SELECT 1 FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.verification_status = 'verified'
      AND site.reviewed_by = 'system:structured-ats-rank1-v2'
);

CREATE OR REPLACE VIEW jobpush.crawl_schedule_queue AS
SELECT
    target.priority_tier,
    target.priority_score,
    target.consolidation_key,
    target.canonical_name,
    site.site_id,
    site.source_type,
    site.site_url,
    site.scope_method,
    CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
    END AS recommended_interval_hours,
    site.last_crawled_at,
    site.last_success_at,
    site.next_crawl_at,
    COALESCE(site.next_crawl_at, now()) <= now() AS is_due,
    site.consecutive_failures,
    site.crawl_status
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.source_type IN (
      'apple_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday',
      'lever', 'ashby', 'smartrecruiters'
  );

UPDATE jobpush.career_sites site
SET crawl_interval_hours = CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
    END,
    next_crawl_at = COALESCE(
        site.next_crawl_at,
        site.last_success_at + make_interval(hours => CASE target.priority_tier
            WHEN 'P0' THEN 24 WHEN 'P1' THEN 72 WHEN 'P2' THEN 168 END),
        now()
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.source_type IN (
      'apple_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday',
      'lever', 'ashby', 'smartrecruiters'
  );

COMMENT ON VIEW jobpush.career_site_selection_candidates IS
    'System site-selection scoring surface. Human labels remain authoritative; rank-1 structured ATS candidates can be auto-trusted when adapter support and US filtering exist.';

COMMIT;
