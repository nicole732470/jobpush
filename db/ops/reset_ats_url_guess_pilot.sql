\pset pager off

BEGIN;

WITH guessed_companies AS (
    SELECT DISTINCT consolidation_key
    FROM jobpush.career_sites
    WHERE discovery_source = 'ats_url_guess'
      AND verification_status = 'unverified'
),
deleted AS (
    DELETE FROM jobpush.career_sites
    WHERE discovery_source = 'ats_url_guess'
      AND verification_status = 'unverified'
    RETURNING consolidation_key
),
reset_generic AS (
    UPDATE jobpush.career_sites site
    SET last_error = NULL,
        updated_at = now()
    WHERE site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND site.last_error LIKE 'ats_url_guess_attempted:%'
      AND site.consolidation_key IN (SELECT consolidation_key FROM guessed_companies)
    RETURNING site.site_id
)
SELECT
    (SELECT count(*) FROM deleted) AS deleted_guess_sites,
    (SELECT count(*) FROM reset_generic) AS reset_generic_sites;

COMMIT;
