WITH mapping_resolution AS (
    SELECT
        lower(btrim(normalized_job_title)) AS normalized_title,
        count(DISTINCT mapping.normalized_soc_code) AS matched_soc_count,
        count(DISTINCT mapping.normalized_soc_code) FILTER (WHERE target.normalized_soc_code IS NOT NULL) AS target_soc_count,
        count(DISTINCT mapping.normalized_soc_code) FILTER (WHERE target.normalized_soc_code IS NULL) AS non_target_soc_count
    FROM jobpush.soc_role_title_mappings mapping
    LEFT JOIN jobpush.target_soc_roles target
      ON target.normalized_soc_code = mapping.normalized_soc_code
     AND target.active
    GROUP BY lower(btrim(normalized_job_title))
), observed AS (
    SELECT posting.normalized_title,
           count(*) AS active_us_postings,
           count(DISTINCT posting.consolidation_key) AS companies
    FROM jobpush.job_postings posting
    WHERE posting.active AND posting.market_scope = 'US'
    GROUP BY posting.normalized_title
), classified AS (
    SELECT observed.*,
           CASE
             WHEN mapping.normalized_title IS NULL THEN 'no_exact_match'
             WHEN mapping.target_soc_count > 0 AND mapping.non_target_soc_count = 0 THEN 'auto_target'
             WHEN mapping.target_soc_count = 0 AND mapping.non_target_soc_count > 0 THEN 'auto_non_target'
             ELSE 'soc_conflict_review'
           END AS match_result
    FROM observed
    LEFT JOIN mapping_resolution mapping USING (normalized_title)
)
SELECT match_result,
       count(*) AS distinct_titles,
       sum(active_us_postings) AS active_us_postings,
       round(100.0 * sum(active_us_postings) / sum(sum(active_us_postings)) OVER (), 2) AS posting_pct
FROM classified
GROUP BY match_result
ORDER BY active_us_postings DESC;

\echo '=== Existing manual/automatic label state ==='
SELECT label.classification_status, count(*) AS distinct_titles
FROM jobpush.job_title_labels label
GROUP BY label.classification_status
ORDER BY label.classification_status;
