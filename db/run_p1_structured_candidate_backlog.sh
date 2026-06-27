#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off -c "
WITH p1 AS (
    SELECT consolidation_key, canonical_name, priority_score
    FROM jobpush.crawl_targets
    WHERE enabled AND priority_tier = 'P1'
),
verified AS (
    SELECT DISTINCT consolidation_key
    FROM jobpush.career_sites
    WHERE verification_status = 'verified'
),
candidate AS (
    SELECT p1.canonical_name,
           p1.priority_score,
           site.source_type,
           site.normalized_domain,
           site.site_url,
           site.candidate_rank
    FROM p1
    JOIN jobpush.career_sites site USING (consolidation_key)
    LEFT JOIN verified USING (consolidation_key)
    WHERE verified.consolidation_key IS NULL
      AND site.verification_status = 'unverified'
      AND site.source_type <> 'generic_html'
)
SELECT source_type,
       normalized_domain,
       count(*) AS candidate_sites,
       count(DISTINCT canonical_name) AS companies,
       min(candidate_rank) AS best_rank,
       max(priority_score) AS max_priority_score
FROM candidate
GROUP BY source_type, normalized_domain
ORDER BY companies DESC, source_type, normalized_domain;

WITH p1 AS (
    SELECT consolidation_key, canonical_name, priority_score
    FROM jobpush.crawl_targets
    WHERE enabled AND priority_tier = 'P1'
),
verified AS (
    SELECT DISTINCT consolidation_key
    FROM jobpush.career_sites
    WHERE verification_status = 'verified'
),
candidate AS (
    SELECT p1.canonical_name,
           p1.priority_score,
           site.source_type,
           site.normalized_domain,
           site.site_url,
           site.candidate_rank
    FROM p1
    JOIN jobpush.career_sites site USING (consolidation_key)
    LEFT JOIN verified USING (consolidation_key)
    WHERE verified.consolidation_key IS NULL
      AND site.verification_status = 'unverified'
      AND site.source_type <> 'generic_html'
)
SELECT source_type,
       candidate_rank,
       canonical_name,
       priority_score,
       site_url
FROM candidate
ORDER BY priority_score DESC, candidate_rank, canonical_name
LIMIT 80;
"
