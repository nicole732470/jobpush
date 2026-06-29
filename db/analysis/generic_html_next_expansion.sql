\pset pager off

WITH generic AS (
  SELECT DISTINCT ON (target.consolidation_key)
      target.consolidation_key,
      target.canonical_name,
      target.priority_tier,
      target.priority_score,
      site.site_id,
      site.site_url,
      site.normalized_domain,
      COALESCE(site.last_error, '') AS last_error
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P0','P1')
    AND site.source_type = 'generic_html'
    AND site.verification_status = 'unverified'
    AND site.crawl_enabled = FALSE
    AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
    )
  ORDER BY target.consolidation_key, target.priority_tier, target.priority_score DESC NULLS LAST,
           site.candidate_score DESC NULLS LAST
)
SELECT
  COUNT(*) AS generic_blocked_companies,
  COUNT(*) FILTER (WHERE last_error NOT LIKE 'generic_ats_resolution_attempted%') AS ats_link_not_attempted,
  COUNT(*) FILTER (WHERE last_error NOT LIKE 'generic_jsonld_checked%') AS jsonld_not_attempted,
  COUNT(*) FILTER (WHERE last_error LIKE 'generic_ats_resolution_attempted%') AS ats_link_attempted,
  COUNT(*) FILTER (WHERE last_error LIKE 'generic_jsonld_checked%') AS jsonld_attempted
FROM generic;

WITH generic AS (
  SELECT DISTINCT ON (target.consolidation_key)
      target.consolidation_key,
      target.canonical_name,
      target.priority_tier,
      target.priority_score,
      site.site_id,
      site.site_url,
      site.normalized_domain,
      COALESCE(site.last_error, '') AS last_error
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P0','P1')
    AND site.source_type = 'generic_html'
    AND site.verification_status = 'unverified'
    AND site.crawl_enabled = FALSE
    AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
    )
  ORDER BY target.consolidation_key, target.priority_tier, target.priority_score DESC NULLS LAST,
           site.candidate_score DESC NULLS LAST
)
SELECT normalized_domain, COUNT(*) AS companies, MIN(site_url) AS example_url
FROM generic
GROUP BY normalized_domain
ORDER BY companies DESC, normalized_domain
LIMIT 40;

WITH generic AS (
  SELECT DISTINCT ON (target.consolidation_key)
      target.canonical_name,
      target.priority_tier,
      target.priority_score,
      site.site_url,
      COALESCE(site.last_error, '') AS last_error
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P0','P1')
    AND site.source_type = 'generic_html'
    AND site.verification_status = 'unverified'
    AND site.crawl_enabled = FALSE
    AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
    )
  ORDER BY target.consolidation_key, target.priority_tier, target.priority_score DESC NULLS LAST,
           site.candidate_score DESC NULLS LAST
)
SELECT canonical_name, priority_score, site_url, last_error
FROM generic
ORDER BY priority_tier, priority_score DESC NULLS LAST, canonical_name
LIMIT 40;
