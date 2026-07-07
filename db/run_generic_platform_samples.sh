#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
WITH best_generic AS (
    SELECT DISTINCT ON (target.consolidation_key)
        target.consolidation_key,
        target.canonical_name,
        target.priority_tier,
        target.priority_score,
        site.site_id,
        site.site_url,
        site.normalized_domain,
        COALESCE(site.candidate_score, 0) AS candidate_score
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
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
    ORDER BY target.consolidation_key,
             site.candidate_score DESC NULLS LAST,
             site.candidate_rank NULLS LAST,
             site.site_id
), platform AS (
    SELECT *,
           CASE
             WHEN normalized_domain = 'jobs.digitalhire.com' THEN 'digitalhire'
             WHEN normalized_domain LIKE '%.catsone.com' OR normalized_domain = 'catsone.com' THEN 'catsone'
             WHEN normalized_domain = 'recruit.hirebridge.com' THEN 'hirebridge'
             WHEN normalized_domain LIKE '%.breezy.hr' OR normalized_domain = 'breezy.hr' THEN 'breezy'
             WHEN normalized_domain LIKE '%.trakstar.com' OR normalized_domain = 'trakstar.com' THEN 'trakstar'
             WHEN normalized_domain LIKE '%.hireology.com' OR normalized_domain = 'hireology.com' THEN 'hireology'
           END AS platform_name
    FROM best_generic
)
SELECT platform_name,
       normalized_domain,
       COUNT(*) AS companies,
       string_agg(DISTINCT priority_tier, ', ' ORDER BY priority_tier) AS tiers,
       max(priority_score) AS max_priority_score,
       max(candidate_score) AS max_candidate_score,
       min(site_url) AS example_url
FROM platform
WHERE platform_name IS NOT NULL
GROUP BY 1, 2
ORDER BY companies DESC, max_priority_score DESC, max_candidate_score DESC;

\echo '=== 5 samples per platform ==='
WITH best_generic AS (
    SELECT DISTINCT ON (target.consolidation_key)
        target.consolidation_key,
        target.canonical_name,
        target.priority_tier,
        target.priority_score,
        site.site_id,
        site.site_url,
        site.normalized_domain,
        COALESCE(site.candidate_score, 0) AS candidate_score
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
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
    ORDER BY target.consolidation_key,
             site.candidate_score DESC NULLS LAST,
             site.candidate_rank NULLS LAST,
             site.site_id
), platform AS (
    SELECT *,
           CASE
             WHEN normalized_domain = 'jobs.digitalhire.com' THEN 'digitalhire'
             WHEN normalized_domain LIKE '%.catsone.com' OR normalized_domain = 'catsone.com' THEN 'catsone'
             WHEN normalized_domain = 'recruit.hirebridge.com' THEN 'hirebridge'
             WHEN normalized_domain LIKE '%.breezy.hr' OR normalized_domain = 'breezy.hr' THEN 'breezy'
             WHEN normalized_domain LIKE '%.trakstar.com' OR normalized_domain = 'trakstar.com' THEN 'trakstar'
             WHEN normalized_domain LIKE '%.hireology.com' OR normalized_domain = 'hireology.com' THEN 'hireology'
           END AS platform_name
    FROM best_generic
), ranked AS (
    SELECT *, row_number() OVER (PARTITION BY platform_name ORDER BY priority_tier, priority_score DESC, candidate_score DESC, site_id) AS rn
    FROM platform
    WHERE platform_name IS NOT NULL
)
SELECT platform_name, rn, priority_tier, priority_score, candidate_score,
       site_id, canonical_name, normalized_domain, site_url
FROM ranked
WHERE rn <= 5
ORDER BY platform_name, rn;
SQL
