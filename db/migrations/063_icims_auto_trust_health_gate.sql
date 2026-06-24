BEGIN;

-- The first scaled sample produced 0/3 successful auto-trusted iCIMS runs
-- because those pages did not expose a safe US location option. Return the
-- untouched auto-trusted iCIMS cohort to review; human-confirmed iCIMS sites
-- are not changed. Greenhouse and Workday remain enabled.
UPDATE jobpush.career_sites
SET verification_status = 'unverified',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    target_country_code = NULL,
    scope_method = 'unknown',
    next_crawl_at = NULL,
    reviewed_at = NULL,
    reviewed_by = NULL,
    review_notes = 'Auto-trust rolled back after initial iCIMS US-scope health gate failed',
    updated_at = now()
WHERE verification_status = 'verified'
  AND source_type = 'icims'
  AND reviewed_by = 'system:structured-ats-rank1-v1';

UPDATE jobpush.crawl_targets target
SET discovery_status = 'review_pending', updated_at = now()
WHERE EXISTS (
    SELECT 1 FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.source_type = 'icims'
      AND site.verification_status = 'unverified'
      AND site.review_notes LIKE 'Auto-trust rolled back%%'
)
AND NOT EXISTS (
    SELECT 1 FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.verification_status = 'verified'
);

COMMIT;
