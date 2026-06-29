#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${GENERIC_JSONLD_LIMIT:-1000}"
TIERS="${GENERIC_JSONLD_TIERS:-P0,P1,P2,P3}"
TIER_ARRAY="ARRAY[$(
  printf "%s" "$TIERS" | tr ',' '\n' | awk 'NF {gsub(/'\''/, ""); printf "%s'\''%s'\''", sep, $1; sep=","}'
)]"
WORK_DIR="$(mktemp -d -t jobpush-generic-jsonld.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
TARGETS="$WORK_DIR/targets.csv"
RESULTS="$WORK_DIR/results.csv"

"${PSQL[@]}" -c "\copy (
  SELECT DISTINCT ON (target.consolidation_key)
      site.site_id,
      site.consolidation_key,
      target.canonical_name,
      site.site_url
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier = ANY($TIER_ARRAY)
    AND site.source_type = 'generic_html'
    AND site.verification_status = 'unverified'
    AND site.crawl_enabled = FALSE
    AND COALESCE(site.last_error, '') NOT LIKE 'generic_jsonld_checked%'
    AND NOT EXISTS (
        SELECT 1
        FROM jobpush.career_sites verified
        WHERE verified.consolidation_key = site.consolidation_key
          AND verified.verification_status = 'verified'
    )
  ORDER BY target.consolidation_key, target.priority_tier, target.priority_score DESC NULLS LAST,
           site.candidate_score DESC NULLS LAST, site.candidate_rank NULLS LAST
  LIMIT $LIMIT
) TO '$TARGETS' WITH (FORMAT csv, HEADER true)"

TARGET_COUNT=$(( $(wc -l < "$TARGETS") - 1 ))
if [[ "$TARGET_COUNT" -le 0 ]]; then
  echo "No generic HTML candidates require JSON-LD probing."
  exit 0
fi

echo "Checking $TARGET_COUNT generic HTML candidates for JobPosting JSON-LD; credits used: 0"
python3 "$REPO_DIR/scripts/find_generic_jsonld_sites.py" "$TARGETS" "$RESULTS" --timeout 8 --workers 8

"${PSQL[@]}" <<SQL
CREATE TEMP TABLE generic_jsonld_probe (
    site_id BIGINT,
    consolidation_key TEXT,
    canonical_name TEXT,
    site_url TEXT,
    jobposting_count INTEGER,
    error_message TEXT
);
\copy generic_jsonld_probe FROM '$RESULTS' WITH (FORMAT csv, HEADER true)

UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'system:generic-jsonld-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Auto-enabled generic page with JobPosting JSON-LD'),
    last_error = NULL,
    updated_at = now()
FROM generic_jsonld_probe probe
WHERE site.site_id = probe.site_id
  AND probe.jobposting_count > 0;

UPDATE jobpush.career_sites site
SET last_error = 'generic_jsonld_checked: no JobPosting JSON-LD found',
    updated_at = now()
FROM generic_jsonld_probe probe
WHERE site.site_id = probe.site_id
  AND probe.jobposting_count = 0
  AND COALESCE(probe.error_message, '') = '';

UPDATE jobpush.career_sites site
SET last_error = 'generic_jsonld_checked: ' || left(probe.error_message, 450),
    updated_at = now()
FROM generic_jsonld_probe probe
WHERE site.site_id = probe.site_id
  AND COALESCE(probe.error_message, '') <> '';

SELECT
    count(*) AS checked,
    count(*) FILTER (WHERE jobposting_count > 0) AS promoted,
    sum(jobposting_count) AS jsonld_jobpostings
FROM generic_jsonld_probe;
SQL
