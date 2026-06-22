BEGIN;

CREATE OR REPLACE VIEW jobpush.job_title_soc_match_candidates AS
WITH mapping_resolution AS (
    SELECT
        lower(btrim(mapping.normalized_job_title)) AS normalized_title,
        count(DISTINCT mapping.normalized_soc_code) AS matched_soc_count,
        count(DISTINCT mapping.normalized_soc_code)
            FILTER (WHERE target.normalized_soc_code IS NOT NULL) AS target_soc_count,
        count(DISTINCT mapping.normalized_soc_code)
            FILTER (WHERE target.normalized_soc_code IS NULL) AS non_target_soc_count,
        string_agg(DISTINCT mapping.normalized_soc_code, ', ' ORDER BY mapping.normalized_soc_code) AS matched_soc_codes,
        string_agg(DISTINCT mapping.soc_title, ' | ' ORDER BY mapping.soc_title) AS matched_soc_titles,
        string_agg(DISTINCT target.representative_title, ' | ' ORDER BY target.representative_title)
            FILTER (WHERE target.normalized_soc_code IS NOT NULL) AS target_soc_titles
    FROM jobpush.soc_role_title_mappings mapping
    LEFT JOIN jobpush.target_soc_roles target
      ON target.normalized_soc_code = mapping.normalized_soc_code
     AND target.active
    GROUP BY lower(btrim(mapping.normalized_job_title))
)
SELECT
    catalog.normalized_title,
    catalog.example_title,
    catalog.active_posting_count,
    catalog.company_count,
    mapping.matched_soc_count,
    mapping.target_soc_count,
    mapping.non_target_soc_count,
    mapping.matched_soc_codes,
    mapping.matched_soc_titles,
    mapping.target_soc_titles,
    CASE
      WHEN mapping.normalized_title IS NULL THEN 'review'
      WHEN mapping.target_soc_count > 0 AND mapping.non_target_soc_count = 0 THEN 'target'
      WHEN mapping.target_soc_count = 0 AND mapping.non_target_soc_count > 0 THEN 'non_target'
      ELSE 'review'
    END AS suggested_status,
    CASE
      WHEN mapping.normalized_title IS NULL THEN 'no_exact_raw_title_match'
      WHEN mapping.target_soc_count > 0 AND mapping.non_target_soc_count = 0 THEN 'exact_target_soc_only'
      WHEN mapping.target_soc_count = 0 AND mapping.non_target_soc_count > 0 THEN 'exact_non_target_soc_only'
      ELSE 'mixed_soc_conflict'
    END AS suggestion_reason
FROM jobpush.job_title_catalog catalog
LEFT JOIN mapping_resolution mapping USING (normalized_title);

UPDATE jobpush.job_title_labels label
SET classification_status = candidate.suggested_status,
    canonical_role = CASE
        WHEN candidate.suggested_status = 'target' THEN candidate.target_soc_titles
        ELSE candidate.matched_soc_titles
    END,
    rule_version = 'soc-exact-v1',
    decision_reason = candidate.suggestion_reason || ': ' || candidate.matched_soc_codes,
    labeled_by = 'system:soc-exact-v1',
    labeled_at = now(),
    updated_at = now()
FROM jobpush.job_title_soc_match_candidates candidate
WHERE label.normalized_title = candidate.normalized_title
  AND candidate.suggested_status IN ('target', 'non_target')
  AND label.classification_status = 'review'
  AND label.labeled_by IS NULL;

CREATE OR REPLACE VIEW jobpush.job_title_review_queue AS
SELECT
    candidate.normalized_title,
    candidate.example_title,
    candidate.active_posting_count,
    candidate.company_count,
    candidate.suggested_status,
    candidate.suggestion_reason,
    candidate.matched_soc_codes,
    candidate.matched_soc_titles,
    label.classification_status,
    label.canonical_role,
    label.decision_reason,
    label.labeled_by,
    label.updated_at
FROM jobpush.job_title_soc_match_candidates candidate
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE label.classification_status = 'review'
ORDER BY candidate.active_posting_count DESC, candidate.company_count DESC,
         candidate.normalized_title;

COMMIT;
