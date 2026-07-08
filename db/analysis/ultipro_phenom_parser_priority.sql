\pset pager off

\echo '=== Ultipro/Phenom candidate inventory by tier ==='
SELECT
    target.priority_tier,
    site.source_type,
    site.verification_status,
    site.crawl_enabled,
    count(*) AS site_rows,
    count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2', 'P3')
  AND site.source_type IN ('ultipro', 'phenom', 'talentbrew')
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, companies DESC;

\echo '=== Ultipro top URL patterns (unverified blockers) ==='
SELECT
    site.normalized_domain,
    regexp_replace(
        regexp_replace(lower(site.site_url), '^https?://[^/]+', ''),
        '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}.*$',
        '/{uuid}',
        'g'
    ) AS url_path_pattern,
    count(DISTINCT site.consolidation_key) AS companies,
    count(*) AS site_rows,
    round(avg(target.priority_score), 2) AS avg_priority_score,
    max(target.priority_score) AS max_priority_score
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND site.source_type = 'ultipro'
  AND site.verification_status = 'unverified'
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
GROUP BY 1, 2
ORDER BY companies DESC, max_priority_score DESC NULLS LAST
LIMIT 25;

\echo '=== Phenom top host/path patterns (unverified blockers) ==='
SELECT
    site.normalized_domain,
    split_part(
        regexp_replace(lower(site.site_url), '^https?://[^/]+', ''),
        '/',
        1
    ) AS first_path_segment,
    count(DISTINCT site.consolidation_key) AS companies,
    count(*) AS site_rows,
    round(avg(target.priority_score), 2) AS avg_priority_score,
    max(target.priority_score) AS max_priority_score
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND site.source_type = 'phenom'
  AND site.verification_status = 'unverified'
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
GROUP BY 1, 2
ORDER BY companies DESC, max_priority_score DESC NULLS LAST
LIMIT 25;

\echo '=== Ultipro/Phenom hidden in generic_html (missed classification) ==='
SELECT
    target.priority_tier,
    CASE
        WHEN site.normalized_domain ~* 'ultipro' OR site.site_url ~* 'ultipro' THEN 'ultipro_signal'
        WHEN site.normalized_domain ~* 'phenom' OR site.site_url ~* 'phenom' THEN 'phenom_signal'
        WHEN site.normalized_domain ~* 'talentbrew' OR site.site_url ~* 'talentbrew' THEN 'talentbrew_signal'
        ELSE 'other'
    END AS platform_signal,
    count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2', 'P3')
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND (
      site.normalized_domain ~* '(ultipro|phenom|talentbrew)'
      OR site.site_url ~* '(ultipro|phenom|talentbrew)'
  )
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
GROUP BY 1, 2
ORDER BY 1, companies DESC;

\echo '=== P2/P3 top Ultipro companies (for parser pilot) ==='
SELECT target.priority_tier, target.priority_score, target.canonical_name, site.site_url, site.candidate_rank
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.source_type = 'ultipro'
  AND site.verification_status = 'unverified'
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
ORDER BY target.priority_tier, target.priority_score DESC NULLS LAST, site.candidate_rank NULLS LAST
LIMIT 20;

\echo '=== P2/P3 top Phenom companies (for parser pilot) ==='
SELECT target.priority_tier, target.priority_score, target.canonical_name, site.normalized_domain, site.site_url, site.candidate_rank
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.source_type = 'phenom'
  AND site.verification_status = 'unverified'
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
ORDER BY target.priority_tier, target.priority_score DESC NULLS LAST, site.candidate_rank NULLS LAST
LIMIT 20;

\echo '=== Cross-tier totals for parser ROI ==='
SELECT
    site.source_type,
    count(DISTINCT site.consolidation_key) FILTER (WHERE target.priority_tier = 'P1') AS p1,
    count(DISTINCT site.consolidation_key) FILTER (WHERE target.priority_tier = 'P2') AS p2,
    count(DISTINCT site.consolidation_key) FILTER (WHERE target.priority_tier = 'P3') AS p3,
    count(DISTINCT site.consolidation_key) AS total
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND site.source_type IN ('ultipro', 'phenom')
  AND site.verification_status = 'unverified'
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
GROUP BY 1
ORDER BY total DESC;
