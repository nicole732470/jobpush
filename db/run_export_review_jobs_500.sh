#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -qAt -c "\copy (
    SELECT
        posting.first_seen_at,
        target.priority_tier,
        target.priority_score,
        target.canonical_name,
        site.source_type,
        label.classification_status AS role_status,
        label.canonical_role,
        posting.title,
        posting.normalized_title,
        posting.location,
        posting.employment_type,
        posting.job_url
    FROM jobpush.job_postings_us posting
    JOIN jobpush.career_sites site
      ON site.site_id = posting.site_id
    JOIN jobpush.crawl_targets target
      ON target.consolidation_key = posting.consolidation_key
    JOIN jobpush.job_title_labels label
      ON label.normalized_title = posting.normalized_title
    WHERE posting.active
      AND label.classification_status = 'review'
      AND target.enabled
    ORDER BY
        CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
        posting.first_seen_at DESC,
        target.priority_score DESC NULLS LAST,
        target.canonical_name,
        posting.title
    LIMIT 500
) TO STDOUT WITH CSV HEADER"
