\pset pager off
SELECT target.canonical_name, site.site_url, site.source_key, site.candidate_rank, site.evidence_title
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled AND target.priority_tier='P1'
  AND site.source_type='successfactors'
  AND site.verification_status='unverified'
ORDER BY target.priority_score DESC NULLS LAST, site.candidate_rank NULLS LAST
LIMIT 40;
