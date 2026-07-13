#!/usr/bin/env bash
# Drain P2/P3 generic-only backlog via zero-credit hidden-ATS link resolution.
# Then auto-trust + ATS URL guess on whatever remains.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

GENERIC_RESOLVE_ROUNDS="${GENERIC_RESOLVE_ROUNDS:-3}"
GENERIC_RESOLVE_LIMIT="${GENERIC_RESOLVE_LIMIT:-1500}"
GENERIC_RESOLVE_TIERS="${GENERIC_RESOLVE_TIERS:-P2,P3}"
GENERIC_RESOLVE_RETRY="${GENERIC_RESOLVE_RETRY:-0}"
ATS_GUESS_LIMIT="${ATS_GUESS_LIMIT:-500}"

snapshot() {
  local label="$1"
  echo "=== Snapshot: $label ==="
  "${PSQL[@]}" -P pager=off <<'SQL'
SELECT target.priority_tier,
       count(DISTINCT target.consolidation_key) AS enabled_companies
FROM jobpush.crawl_targets target
WHERE target.enabled
  AND target.priority_tier IN ('P2','P3')
  AND EXISTS (
      SELECT 1 FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.verification_status = 'verified'
        AND site.crawl_enabled
  )
GROUP BY 1
ORDER BY 1;

SELECT count(*) AS resolver_fresh_eligible
FROM (
  SELECT DISTINCT ON (target.consolidation_key) site.site_id
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P2','P3')
    AND site.source_type = 'generic_html'
    AND site.verification_status = 'unverified'
    AND site.crawl_enabled = FALSE
    AND COALESCE(site.last_error, '') NOT LIKE 'generic_ats_resolution_attempted:v2%'
    AND NOT EXISTS (
        SELECT 1
        FROM jobpush.career_sites structured
        WHERE structured.consolidation_key = site.consolidation_key
          AND structured.source_type <> 'generic_html'
          AND structured.verification_status IN ('verified', 'unverified')
    )
  ORDER BY target.consolidation_key, target.priority_tier, target.priority_score DESC NULLS LAST,
           site.candidate_score DESC NULLS LAST, site.candidate_rank NULLS LAST
) x;
SQL
}

snapshot "before"

echo "=== Generic resolver wave: tiers=$GENERIC_RESOLVE_TIERS limit=$GENERIC_RESOLVE_LIMIT rounds=$GENERIC_RESOLVE_ROUNDS retry=$GENERIC_RESOLVE_RETRY ==="
completed_rounds=0
for round in $(seq 1 "$GENERIC_RESOLVE_ROUNDS"); do
  echo "=== Round $round/$GENERIC_RESOLVE_ROUNDS: resolve generic HTML → ATS links ==="
  round_log="$(mktemp -t jobpush-resolve-round.XXXXXX.log)"
  if ! GENERIC_RESOLVE_LIMIT="$GENERIC_RESOLVE_LIMIT" \
      GENERIC_RESOLVE_TIERS="$GENERIC_RESOLVE_TIERS" \
      GENERIC_RESOLVE_RETRY="$GENERIC_RESOLVE_RETRY" \
      bash "$SCRIPT_DIR/run_resolve_generic_html_ats_links.sh" >"$round_log" 2>&1; then
    tail -n 80 "$round_log"
    rm -f "$round_log"
    exit 1
  fi
  # Summarize for SSM; keep full log locally on the instance only briefly.
  grep -E '^(No generic HTML|Resolving ATS|COPY |Inserted |Updated |===)' "$round_log" || true
  grep -E 'ATS links$' "$round_log" | awk -F': ' '$2+0>0 {print}' | tail -n 40 || true
  hits=$(grep -E 'ATS links$' "$round_log" | awk -F': ' '$2+0>0' | wc -l | tr -d ' ')
  echo "Round $round hits (companies with >=1 ATS link): $hits"
  if grep -q "No generic HTML candidates require ATS-link resolution." "$round_log"; then
    rm -f "$round_log"
    echo "Resolver backlog exhausted after $completed_rounds full round(s)."
    break
  fi
  rm -f "$round_log"

  completed_rounds=$round
  echo "=== Round $round auto-trust ==="
  bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"
done

echo "=== ATS URL guess on remaining generic-only (limit=$ATS_GUESS_LIMIT) ==="
ATS_GUESS_TIERS=P2,P3 ATS_GUESS_LIMIT="$ATS_GUESS_LIMIT" bash "$SCRIPT_DIR/run_guess_ats_sites.sh" || true
bash "$SCRIPT_DIR/run_remove_dangerous_ats_url_guess_slugs.sh" || true
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

snapshot "after ($completed_rounds resolver rounds)"

echo "=== New resolver/guess candidates still unverified (top sources) ==="
"${PSQL[@]}" -P pager=off <<'SQL'
SELECT site.discovery_source, site.source_type, site.verification_status,
       count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P2','P3')
  AND site.discovery_source IN ('generic_html_link_resolver', 'ats_url_guess')
  AND site.updated_at > now() - interval '6 hours'
GROUP BY 1,2,3
ORDER BY companies DESC
LIMIT 40;
SQL
