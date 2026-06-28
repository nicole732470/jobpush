\pset pager off

SELECT
    target.consolidation_key,
    target.canonical_name,
    target.priority_tier,
    site.site_id,
    site.source_type,
    site.normalized_domain,
    site.site_url,
    site.verification_status,
    site.crawl_enabled,
    site.evidence_title,
    left(site.evidence_snippet, 300) AS evidence_snippet
FROM jobpush.crawl_targets target
JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P0'
  AND site.source_type = 'generic_html'
ORDER BY target.canonical_name, site.candidate_rank NULLS LAST, site.site_id;
