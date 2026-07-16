-- Refresh only live eligibility. The inventory is maintained by the crawl
-- pipeline; rebuilding it from historical postings makes the dashboard slow.
\if :{?refresh_since}
\else
\set refresh_since 'epoch'
\endif

BEGIN;

-- Snapshot rows are keyed by (site_id, external_job_id).  A hash join would
-- scan every historical raw HTML blob; indexed lookups are far cheaper here.
SET LOCAL enable_hashjoin = off;

-- The fast table is an inventory, not merely an eligibility cache.  New
-- postings must exist here before their first JD is available; otherwise the
-- export pipeline cannot select them for JD retrieval.
WITH ranked_targets AS (
  SELECT target.*,
         ROW_NUMBER() OVER (
           PARTITION BY target.priority_tier
           ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name
         ) AS priority_rank_in_tier
  FROM jobpush.crawl_targets target
  WHERE target.enabled
), incoming AS (
  SELECT posting.site_id, posting.external_job_id, posting.consolidation_key,
         target.canonical_name, target.priority_tier, target.priority_score,
         target.priority_rank_in_tier, posting.title, posting.normalized_title,
         posting.location, posting.category, posting.employment_type,
         CASE WHEN label.classification_status = 'non_target' THEN 'non_target' ELSE 'review' END AS role_status,
         CASE WHEN label.classification_status = 'non_target' THEN NULL ELSE label.canonical_role END AS canonical_role,
         CASE
           WHEN label.canonical_role = 'candidate_profile_track: product' THEN 'stack_1_business_product_data'
           WHEN label.canonical_role = 'candidate_profile_track: analyst/bi' THEN 'stack_1_business_product_data'
           WHEN label.canonical_role = 'candidate_profile_track: applied_ai' THEN 'stack_2_ai_solutions_systems_data'
           WHEN label.canonical_role = 'candidate_profile_track: solutions/systems' THEN 'stack_2_ai_solutions_systems_data'
           WHEN label.canonical_role = 'candidate_profile_track: customer_success' THEN 'stack_3_customer_success'
           ELSE 'stack_5_possible_target'
         END AS role_stack,
         CASE
           WHEN label.canonical_role = 'candidate_profile_track: product' THEN 'product_manager'
           WHEN label.canonical_role = 'candidate_profile_track: analyst/bi' THEN 'data_analytics_bi'
           WHEN label.canonical_role = 'candidate_profile_track: applied_ai' THEN 'applied_ai'
           WHEN label.canonical_role = 'candidate_profile_track: solutions/systems' THEN 'systems_engineering'
           WHEN label.canonical_role = 'candidate_profile_track: customer_success' THEN 'customer_success'
           ELSE concat('title:', COALESCE(NULLIF(posting.normalized_title, ''), 'unclassified'))
         END AS role_family,
         CASE
           WHEN posting.normalized_title ~* '(^|[^a-z])(intern|internship|new grad|campus|university)([^a-z]|$)' THEN 'new_grad'
           WHEN posting.normalized_title ~* '(^|[^a-z])(senior|sr\.?)([^a-z]|$)' THEN 'senior'
           ELSE 'standard'
         END AS seniority_bucket,
         COALESCE(NULLIF(lower(posting.employment_type), ''), 'unknown') AS employment_bucket,
         CASE
           WHEN COALESCE(posting.location, '') ILIKE '%remote%' THEN 'remote'
           WHEN COALESCE(posting.location, '') ~* 'chicago|illinois|(^|[,/ -])il($|[,/ -])' THEN 'chicago_il'
           ELSE 'other_us'
         END AS location_bucket,
         posting.first_seen_at, posting.last_seen_at, posting.job_url
  FROM jobpush.job_postings posting
  JOIN ranked_targets target USING (consolidation_key)
  LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
  WHERE posting.active AND posting.market_scope = 'US'
)
INSERT INTO jobpush.dashboard_jobs_fast (
  site_id, external_job_id, consolidation_key, canonical_name, priority_tier,
  priority_score, priority_rank_in_tier, title, normalized_title, location,
  category, employment_type, role_status, canonical_role, role_stack,
  role_family, seniority_bucket, employment_bucket, location_bucket,
  first_seen_at, last_seen_at, job_url
)
SELECT site_id, external_job_id, consolidation_key, canonical_name, priority_tier,
       priority_score, priority_rank_in_tier, title, normalized_title, location,
       category, employment_type, role_status, canonical_role, role_stack,
       role_family, seniority_bucket, employment_bucket, location_bucket,
       first_seen_at, last_seen_at, job_url
FROM incoming
ON CONFLICT (site_id, external_job_id) DO NOTHING;

WITH changed_keys AS MATERIALIZED (
  SELECT site_id, external_job_id
  FROM jobpush.dashboard_jobs_fast
  WHERE first_seen_at >= :'refresh_since'::timestamptz
  UNION
  SELECT fast.site_id, fast.external_job_id
  FROM jobpush.dashboard_jobs_fast fast
  JOIN jobpush.job_title_labels label USING(normalized_title)
  WHERE label.updated_at >= :'refresh_since'::timestamptz
  UNION
  SELECT fast.site_id, fast.external_job_id
  FROM jobpush.job_description_snapshots snapshot
  JOIN jobpush.dashboard_jobs_fast fast USING(site_id,external_job_id)
  WHERE snapshot.updated_at >= :'refresh_since'::timestamptz
), eligibility AS MATERIALIZED (
  SELECT fast.site_id, fast.external_job_id,
         (snapshot.cleaned_description ILIKE '%sponsor%'
          AND jobpush.is_explicit_no_sponsorship(snapshot.cleaned_description)) AS explicit_no_sponsorship,
         snapshot.scrape_status,
         label.classification_status,
         label.canonical_role
  FROM changed_keys changed
  JOIN jobpush.dashboard_jobs_fast fast USING(site_id,external_job_id)
  LEFT JOIN jobpush.job_title_labels label
    ON label.normalized_title = fast.normalized_title
  LEFT JOIN jobpush.job_description_snapshots snapshot
    ON snapshot.site_id = fast.site_id AND snapshot.external_job_id = fast.external_job_id
), classified AS MATERIALIZED (
  SELECT site_id, external_job_id,
         CASE
           WHEN classification_status = 'non_target' THEN 'non_target'
           WHEN scrape_status = 'succeeded' AND explicit_no_sponsorship THEN 'non_target'
           WHEN scrape_status = 'succeeded' THEN COALESCE(classification_status, 'review')
           ELSE 'review'
         END AS role_status,
         CASE
           WHEN classification_status <> 'non_target'
                AND scrape_status = 'succeeded' AND NOT explicit_no_sponsorship
           THEN canonical_role ELSE NULL END AS canonical_role
  FROM eligibility
)
UPDATE jobpush.dashboard_jobs_fast fast
SET role_status = classified.role_status,
    canonical_role = classified.canonical_role
FROM classified
WHERE fast.site_id = classified.site_id AND fast.external_job_id = classified.external_job_id
  AND (fast.role_status, fast.canonical_role) IS DISTINCT FROM (classified.role_status, classified.canonical_role);

COMMIT;
