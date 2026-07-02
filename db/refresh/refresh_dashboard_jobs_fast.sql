-- Refresh the light table used by Jobs to Apply.
-- Application status stays live via job_application_actions in the dashboard query.
BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.dashboard_jobs_fast AS
WITH ranked_targets AS (
    SELECT consolidation_key, priority_score,
           ROW_NUMBER() OVER (
               PARTITION BY priority_tier
               ORDER BY priority_score DESC NULLS LAST, canonical_name
           ) AS priority_rank_in_tier
    FROM jobpush.crawl_targets
    WHERE enabled
), base AS (
    SELECT
        posting.site_id,
        posting.external_job_id,
        posting.consolidation_key,
        target.canonical_name,
        target.priority_tier,
        ranked.priority_score,
        ranked.priority_rank_in_tier,
        posting.title,
        posting.normalized_title,
        posting.location,
        posting.category,
        posting.employment_type,
        COALESCE(label.classification_status, 'review') AS role_status,
        label.canonical_role,
        posting.first_seen_at,
        posting.last_seen_at,
        posting.job_url
    FROM jobpush.job_postings_us posting
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    LEFT JOIN ranked_targets ranked USING (consolidation_key)
    LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
)
SELECT
    site_id,
    external_job_id,
    consolidation_key,
    canonical_name,
    priority_tier,
    priority_score,
    priority_rank_in_tier,
    title,
    normalized_title,
    location,
    category,
    employment_type,
    role_status,
    canonical_role,
               CASE
                   WHEN role_status = 'target' AND canonical_role = 'candidate_profile_track: product' THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND canonical_role = 'candidate_profile_track: analyst/bi' THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%product%manager%'
                       OR normalized_title LIKE '%business%analyst%'
                       OR normalized_title LIKE '%data%analyst%'
                       OR normalized_title LIKE '%strategy%analyst%'
                       OR normalized_title LIKE '%operations%analyst%'
                       OR normalized_title LIKE '%program%manager%'
                       OR normalized_title LIKE '%project%manager%'
                       OR normalized_title LIKE '%implementation%'
                       OR normalized_title LIKE '%consultant%'
                       OR normalized_title LIKE '%consulting%'
                       OR normalized_title LIKE '%coordinator%'
                       OR canonical_role ILIKE '%financial%analyst%'
                       OR canonical_role ILIKE '%financial and investment%'
                       OR canonical_role ILIKE '%market research%'
                   ) THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND canonical_role IN (
                       'candidate_profile_track: solutions/systems',
                       'candidate_profile_track: applied_ai'
                   ) THEN 'stack_2_ai_solutions_systems_data'
                   WHEN role_status = 'target'
                        AND canonical_role = 'candidate_profile_track: software/data'
                        AND (normalized_title LIKE '%data%engineer%'
                             OR normalized_title LIKE '%analytics%engineer%'
                             OR normalized_title LIKE '%data%architect%'
                             OR normalized_title LIKE '%database%administrator%'
                             OR normalized_title LIKE '%database%admin%') THEN 'stack_2_ai_solutions_systems_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%systems%analyst%'
                       OR normalized_title LIKE '%information%system%'
                   ) THEN 'stack_2_ai_solutions_systems_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%software%'
                       OR normalized_title LIKE '%quality%assurance%'
                       OR normalized_title LIKE '% qa %'
                       OR normalized_title LIKE '%test engineer%'
                       OR normalized_title LIKE '%tester%'
                       OR normalized_title LIKE '%devops%'
                       OR normalized_title LIKE '%cloud%'
                       OR normalized_title LIKE '%site reliability%'
                       OR normalized_title LIKE '%sre%'
                       OR normalized_title LIKE '%security%'
                       OR normalized_title LIKE '%cyber%'
                       OR canonical_role ILIKE '%network%'
                       OR canonical_role ILIKE '%systems administrator%'
                       OR canonical_role = 'candidate_profile_track: software/data'
                   ) THEN 'stack_4_sde'
                   WHEN role_status = 'target' AND canonical_role = 'candidate_profile_track: customer_success' THEN 'stack_3_customer_success'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%customer%success%'
                       OR normalized_title LIKE '%technical%account%'
                       OR normalized_title LIKE '%relationship%manager%'
                       OR normalized_title LIKE '%support%'
                       OR normalized_title LIKE '%specialist%'
                       OR normalized_title LIKE '%administrator%'
                       OR normalized_title LIKE '%admin%'
                   ) THEN 'stack_3_customer_success'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%sales%'
                       OR normalized_title LIKE '%marketing%'
                       OR normalized_title LIKE '%business%development%'
                       OR canonical_role = 'candidate_profile_track: marketing automation'
                   ) THEN 'stack_3_gtm'
                   WHEN role_status = 'target' THEN 'stack_5_possible_target'
                   WHEN role_status = 'review' THEN 'needs_review'
                   ELSE 'excluded_non_target'
               END AS role_stack,
               CASE
                   WHEN role_status = 'non_target' THEN 'excluded_non_target'
                   WHEN role_status = 'review' THEN 'needs_review'
                   WHEN canonical_role = 'candidate_profile_track: product' THEN 'product_manager'
                   WHEN canonical_role = 'candidate_profile_track: analyst/bi' THEN 'data_analytics_bi'
                   WHEN canonical_role = 'candidate_profile_track: solutions/systems' THEN 'systems_engineering'
                   WHEN canonical_role = 'candidate_profile_track: applied_ai' THEN 'applied_ai'
                   WHEN canonical_role = 'candidate_profile_track: customer_success' THEN 'customer_success'
                   WHEN canonical_role = 'candidate_profile_track: marketing automation' THEN 'marketing'
                   WHEN canonical_role = 'candidate_profile_track: software/data'
                        AND (normalized_title LIKE '%data%engineer%'
                             OR normalized_title LIKE '%analytics%engineer%'
                             OR normalized_title LIKE '%data%architect%') THEN 'data_engineering'
                   WHEN canonical_role = 'candidate_profile_track: software/data' THEN 'software_engineering'
                   WHEN normalized_title LIKE '%intern%'
                        OR normalized_title LIKE '%internship%'
                        OR normalized_title LIKE '%co op%'
                        OR normalized_title LIKE '%co-op%' THEN 'internship'
                   WHEN normalized_title LIKE '%forward deployed engineer%'
                        OR normalized_title LIKE '%forward-deployed engineer%' THEN 'forward_deployed_engineer'
                   WHEN normalized_title LIKE '%ai full stack%'
                        OR normalized_title LIKE '%ai engineer%'
                        OR normalized_title LIKE '%gtm engineer%' THEN 'applied_ai'
                   WHEN normalized_title LIKE '%product%manager%' THEN 'product_manager'
                   WHEN normalized_title LIKE '%program%manager%' THEN 'program_manager'
                   WHEN normalized_title LIKE '%project%manager%' THEN 'project_manager'
                   WHEN normalized_title LIKE '%system%engineer%'
                        OR normalized_title LIKE '%systems%engineer%'
                        OR normalized_title LIKE '%systems%analyst%'
                        OR normalized_title LIKE '%information%system%' THEN 'systems_engineering'
                   WHEN normalized_title LIKE '%software%engineer%'
                        OR normalized_title LIKE '%software%developer%'
                        OR normalized_title LIKE '%fullstack%'
                        OR normalized_title LIKE '%full stack%' THEN 'software_engineering'
                   WHEN normalized_title LIKE '%data%scientist%'
                        OR normalized_title LIKE '%machine%learning%'
                        OR normalized_title LIKE '%ml engineer%' THEN 'data_science_ml'
                   WHEN normalized_title LIKE '%data%engineer%'
                        OR normalized_title LIKE '%analytics%engineer%'
                        OR normalized_title LIKE '%data%architect%'
                        OR normalized_title LIKE '%database%administrator%'
                        OR normalized_title LIKE '%database%admin%' THEN 'data_engineering'
                   WHEN normalized_title LIKE '%data%analyst%'
                        OR normalized_title LIKE '%business intelligence%'
                        OR normalized_title LIKE '%bi analyst%' THEN 'data_analytics_bi'
                   WHEN normalized_title LIKE '%business%analyst%' THEN 'business_analyst'
                   WHEN normalized_title LIKE '%operations%analyst%'
                        OR normalized_title LIKE '%strategy%analyst%' THEN 'strategy_operations'
                   WHEN normalized_title LIKE '%customer%success%'
                        OR normalized_title LIKE '%technical%account%'
                        OR normalized_title LIKE '%relationship%manager%' THEN 'customer_success'
                   WHEN normalized_title LIKE '%technical%support%'
                        OR normalized_title LIKE '%technical%specialist%'
                        OR normalized_title LIKE '%technical%expert%' THEN 'technical_support'
                   WHEN normalized_title LIKE '%marketing%' THEN 'marketing'
                   WHEN normalized_title LIKE '%sales%' THEN 'sales'
                   WHEN canonical_role ILIKE '%market research%' THEN 'marketing'
                   WHEN canonical_role ILIKE '%financial%analyst%'
                        OR canonical_role ILIKE '%financial and investment%' THEN 'financial_analyst'
                   WHEN canonical_role ILIKE '%statistic%' THEN 'data_analytics_bi'
                   WHEN canonical_role ILIKE '%information technology project manager%' THEN 'project_manager'
                   WHEN canonical_role ILIKE '%network%'
                        OR canonical_role ILIKE '%systems administrator%' THEN 'systems_engineering'
                   WHEN canonical_role ILIKE '%software developer%' THEN 'software_engineering'
                   ELSE CONCAT('title:', COALESCE(NULLIF(normalized_title, ''), NULLIF(canonical_role, ''), 'unclassified target title'))
               END AS role_family,
               CASE
                   WHEN normalized_title LIKE '%intern%'
                        OR normalized_title LIKE '%internship%'
                        OR normalized_title LIKE '%co op%'
                        OR normalized_title LIKE '%co-op%' THEN 'internship'
                   WHEN normalized_title LIKE '%new grad%'
                        OR normalized_title LIKE '%university grad%'
                        OR normalized_title LIKE '%entry level%'
                        OR normalized_title LIKE '%early career%' THEN 'entry_level'
                   WHEN normalized_title LIKE '%senior%'
                        OR normalized_title LIKE '%sr %'
                        OR normalized_title LIKE '%staff%'
                        OR normalized_title LIKE '%principal%'
                        OR normalized_title LIKE '%lead%'
                        OR normalized_title LIKE '%director%'
                        OR normalized_title LIKE '%vice president%'
                        OR normalized_title LIKE '%vp%' THEN 'senior_or_leadership'
                   ELSE 'regular_full_time'
               END AS seniority_bucket,
               CASE
                   WHEN normalized_title LIKE '%intern%'
                        OR normalized_title LIKE '%internship%'
                        OR normalized_title LIKE '%co op%'
                        OR normalized_title LIKE '%co-op%' THEN 'internship'
                   WHEN COALESCE(employment_type, '') ILIKE '%contract%'
                        OR normalized_title LIKE '%contract%' THEN 'contract'
                   WHEN COALESCE(employment_type, '') ILIKE '%part%time%'
                        OR normalized_title LIKE '%part time%' THEN 'part_time'
                   WHEN COALESCE(employment_type, '') ILIKE '%full%time%' THEN 'full_time'
                   ELSE 'full_time_or_unknown'
               END AS employment_bucket,
               CASE
                   WHEN COALESCE(location, '') ILIKE '%chicago%'
                        OR COALESCE(location, '') ILIKE '%illinois%'
                        OR COALESCE(location, '') ~* '(^|[,/ -])IL($|[,/ -])' THEN 'chicago_or_illinois'
                   WHEN COALESCE(location, '') ILIKE '%remote%' THEN 'remote'
                   WHEN COALESCE(location, '') = '' THEN 'location_not_listed'
                   ELSE 'other_us'
               END AS location_bucket,
    first_seen_at,
    last_seen_at,
    job_url
FROM base
WITH NO DATA;

TRUNCATE jobpush.dashboard_jobs_fast;

WITH ranked_targets AS (
    SELECT consolidation_key, priority_score,
           ROW_NUMBER() OVER (
               PARTITION BY priority_tier
               ORDER BY priority_score DESC NULLS LAST, canonical_name
           ) AS priority_rank_in_tier
    FROM jobpush.crawl_targets
    WHERE enabled
), base AS (
    SELECT
        posting.site_id,
        posting.external_job_id,
        posting.consolidation_key,
        target.canonical_name,
        target.priority_tier,
        ranked.priority_score,
        ranked.priority_rank_in_tier,
        posting.title,
        posting.normalized_title,
        posting.location,
        posting.category,
        posting.employment_type,
        COALESCE(label.classification_status, 'review') AS role_status,
        label.canonical_role,
        posting.first_seen_at,
        posting.last_seen_at,
        posting.job_url
    FROM jobpush.job_postings_us posting
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    LEFT JOIN ranked_targets ranked USING (consolidation_key)
    LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
)
INSERT INTO jobpush.dashboard_jobs_fast (
    site_id,
    external_job_id,
    consolidation_key,
    canonical_name,
    priority_tier,
    priority_score,
    priority_rank_in_tier,
    title,
    normalized_title,
    location,
    category,
    employment_type,
    role_status,
    canonical_role,
    role_stack,
    role_family,
    seniority_bucket,
    employment_bucket,
    location_bucket,
    first_seen_at,
    last_seen_at,
    job_url
)
SELECT
    site_id,
    external_job_id,
    consolidation_key,
    canonical_name,
    priority_tier,
    priority_score,
    priority_rank_in_tier,
    title,
    normalized_title,
    location,
    category,
    employment_type,
    role_status,
    canonical_role,
               CASE
                   WHEN role_status = 'target' AND canonical_role = 'candidate_profile_track: product' THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND canonical_role = 'candidate_profile_track: analyst/bi' THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%product%manager%'
                       OR normalized_title LIKE '%business%analyst%'
                       OR normalized_title LIKE '%data%analyst%'
                       OR normalized_title LIKE '%strategy%analyst%'
                       OR normalized_title LIKE '%operations%analyst%'
                       OR normalized_title LIKE '%program%manager%'
                       OR normalized_title LIKE '%project%manager%'
                       OR normalized_title LIKE '%implementation%'
                       OR normalized_title LIKE '%consultant%'
                       OR normalized_title LIKE '%consulting%'
                       OR normalized_title LIKE '%coordinator%'
                       OR canonical_role ILIKE '%financial%analyst%'
                       OR canonical_role ILIKE '%financial and investment%'
                       OR canonical_role ILIKE '%market research%'
                   ) THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND canonical_role IN (
                       'candidate_profile_track: solutions/systems',
                       'candidate_profile_track: applied_ai'
                   ) THEN 'stack_2_ai_solutions_systems_data'
                   WHEN role_status = 'target'
                        AND canonical_role = 'candidate_profile_track: software/data'
                        AND (normalized_title LIKE '%data%engineer%'
                             OR normalized_title LIKE '%analytics%engineer%'
                             OR normalized_title LIKE '%data%architect%'
                             OR normalized_title LIKE '%database%administrator%'
                             OR normalized_title LIKE '%database%admin%') THEN 'stack_2_ai_solutions_systems_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%systems%analyst%'
                       OR normalized_title LIKE '%information%system%'
                   ) THEN 'stack_2_ai_solutions_systems_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%software%'
                       OR normalized_title LIKE '%quality%assurance%'
                       OR normalized_title LIKE '% qa %'
                       OR normalized_title LIKE '%test engineer%'
                       OR normalized_title LIKE '%tester%'
                       OR normalized_title LIKE '%devops%'
                       OR normalized_title LIKE '%cloud%'
                       OR normalized_title LIKE '%site reliability%'
                       OR normalized_title LIKE '%sre%'
                       OR normalized_title LIKE '%security%'
                       OR normalized_title LIKE '%cyber%'
                       OR canonical_role ILIKE '%network%'
                       OR canonical_role ILIKE '%systems administrator%'
                       OR canonical_role = 'candidate_profile_track: software/data'
                   ) THEN 'stack_4_sde'
                   WHEN role_status = 'target' AND canonical_role = 'candidate_profile_track: customer_success' THEN 'stack_3_customer_success'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%customer%success%'
                       OR normalized_title LIKE '%technical%account%'
                       OR normalized_title LIKE '%relationship%manager%'
                       OR normalized_title LIKE '%support%'
                       OR normalized_title LIKE '%specialist%'
                       OR normalized_title LIKE '%administrator%'
                       OR normalized_title LIKE '%admin%'
                   ) THEN 'stack_3_customer_success'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%sales%'
                       OR normalized_title LIKE '%marketing%'
                       OR normalized_title LIKE '%business%development%'
                       OR canonical_role = 'candidate_profile_track: marketing automation'
                   ) THEN 'stack_3_gtm'
                   WHEN role_status = 'target' THEN 'stack_5_possible_target'
                   WHEN role_status = 'review' THEN 'needs_review'
                   ELSE 'excluded_non_target'
               END AS role_stack,
               CASE
                   WHEN role_status = 'non_target' THEN 'excluded_non_target'
                   WHEN role_status = 'review' THEN 'needs_review'
                   WHEN canonical_role = 'candidate_profile_track: product' THEN 'product_manager'
                   WHEN canonical_role = 'candidate_profile_track: analyst/bi' THEN 'data_analytics_bi'
                   WHEN canonical_role = 'candidate_profile_track: solutions/systems' THEN 'systems_engineering'
                   WHEN canonical_role = 'candidate_profile_track: applied_ai' THEN 'applied_ai'
                   WHEN canonical_role = 'candidate_profile_track: customer_success' THEN 'customer_success'
                   WHEN canonical_role = 'candidate_profile_track: marketing automation' THEN 'marketing'
                   WHEN canonical_role = 'candidate_profile_track: software/data'
                        AND (normalized_title LIKE '%data%engineer%'
                             OR normalized_title LIKE '%analytics%engineer%'
                             OR normalized_title LIKE '%data%architect%') THEN 'data_engineering'
                   WHEN canonical_role = 'candidate_profile_track: software/data' THEN 'software_engineering'
                   WHEN normalized_title LIKE '%intern%'
                        OR normalized_title LIKE '%internship%'
                        OR normalized_title LIKE '%co op%'
                        OR normalized_title LIKE '%co-op%' THEN 'internship'
                   WHEN normalized_title LIKE '%forward deployed engineer%'
                        OR normalized_title LIKE '%forward-deployed engineer%' THEN 'forward_deployed_engineer'
                   WHEN normalized_title LIKE '%ai full stack%'
                        OR normalized_title LIKE '%ai engineer%'
                        OR normalized_title LIKE '%gtm engineer%' THEN 'applied_ai'
                   WHEN normalized_title LIKE '%product%manager%' THEN 'product_manager'
                   WHEN normalized_title LIKE '%program%manager%' THEN 'program_manager'
                   WHEN normalized_title LIKE '%project%manager%' THEN 'project_manager'
                   WHEN normalized_title LIKE '%system%engineer%'
                        OR normalized_title LIKE '%systems%engineer%'
                        OR normalized_title LIKE '%systems%analyst%'
                        OR normalized_title LIKE '%information%system%' THEN 'systems_engineering'
                   WHEN normalized_title LIKE '%software%engineer%'
                        OR normalized_title LIKE '%software%developer%'
                        OR normalized_title LIKE '%fullstack%'
                        OR normalized_title LIKE '%full stack%' THEN 'software_engineering'
                   WHEN normalized_title LIKE '%data%scientist%'
                        OR normalized_title LIKE '%machine%learning%'
                        OR normalized_title LIKE '%ml engineer%' THEN 'data_science_ml'
                   WHEN normalized_title LIKE '%data%engineer%'
                        OR normalized_title LIKE '%analytics%engineer%'
                        OR normalized_title LIKE '%data%architect%'
                        OR normalized_title LIKE '%database%administrator%'
                        OR normalized_title LIKE '%database%admin%' THEN 'data_engineering'
                   WHEN normalized_title LIKE '%data%analyst%'
                        OR normalized_title LIKE '%business intelligence%'
                        OR normalized_title LIKE '%bi analyst%' THEN 'data_analytics_bi'
                   WHEN normalized_title LIKE '%business%analyst%' THEN 'business_analyst'
                   WHEN normalized_title LIKE '%operations%analyst%'
                        OR normalized_title LIKE '%strategy%analyst%' THEN 'strategy_operations'
                   WHEN normalized_title LIKE '%customer%success%'
                        OR normalized_title LIKE '%technical%account%'
                        OR normalized_title LIKE '%relationship%manager%' THEN 'customer_success'
                   WHEN normalized_title LIKE '%technical%support%'
                        OR normalized_title LIKE '%technical%specialist%'
                        OR normalized_title LIKE '%technical%expert%' THEN 'technical_support'
                   WHEN normalized_title LIKE '%marketing%' THEN 'marketing'
                   WHEN normalized_title LIKE '%sales%' THEN 'sales'
                   WHEN canonical_role ILIKE '%market research%' THEN 'marketing'
                   WHEN canonical_role ILIKE '%financial%analyst%'
                        OR canonical_role ILIKE '%financial and investment%' THEN 'financial_analyst'
                   WHEN canonical_role ILIKE '%statistic%' THEN 'data_analytics_bi'
                   WHEN canonical_role ILIKE '%information technology project manager%' THEN 'project_manager'
                   WHEN canonical_role ILIKE '%network%'
                        OR canonical_role ILIKE '%systems administrator%' THEN 'systems_engineering'
                   WHEN canonical_role ILIKE '%software developer%' THEN 'software_engineering'
                   ELSE CONCAT('title:', COALESCE(NULLIF(normalized_title, ''), NULLIF(canonical_role, ''), 'unclassified target title'))
               END AS role_family,
               CASE
                   WHEN normalized_title LIKE '%intern%'
                        OR normalized_title LIKE '%internship%'
                        OR normalized_title LIKE '%co op%'
                        OR normalized_title LIKE '%co-op%' THEN 'internship'
                   WHEN normalized_title LIKE '%new grad%'
                        OR normalized_title LIKE '%university grad%'
                        OR normalized_title LIKE '%entry level%'
                        OR normalized_title LIKE '%early career%' THEN 'entry_level'
                   WHEN normalized_title LIKE '%senior%'
                        OR normalized_title LIKE '%sr %'
                        OR normalized_title LIKE '%staff%'
                        OR normalized_title LIKE '%principal%'
                        OR normalized_title LIKE '%lead%'
                        OR normalized_title LIKE '%director%'
                        OR normalized_title LIKE '%vice president%'
                        OR normalized_title LIKE '%vp%' THEN 'senior_or_leadership'
                   ELSE 'regular_full_time'
               END AS seniority_bucket,
               CASE
                   WHEN normalized_title LIKE '%intern%'
                        OR normalized_title LIKE '%internship%'
                        OR normalized_title LIKE '%co op%'
                        OR normalized_title LIKE '%co-op%' THEN 'internship'
                   WHEN COALESCE(employment_type, '') ILIKE '%contract%'
                        OR normalized_title LIKE '%contract%' THEN 'contract'
                   WHEN COALESCE(employment_type, '') ILIKE '%part%time%'
                        OR normalized_title LIKE '%part time%' THEN 'part_time'
                   WHEN COALESCE(employment_type, '') ILIKE '%full%time%' THEN 'full_time'
                   ELSE 'full_time_or_unknown'
               END AS employment_bucket,
               CASE
                   WHEN COALESCE(location, '') ILIKE '%chicago%'
                        OR COALESCE(location, '') ILIKE '%illinois%'
                        OR COALESCE(location, '') ~* '(^|[,/ -])IL($|[,/ -])' THEN 'chicago_or_illinois'
                   WHEN COALESCE(location, '') ILIKE '%remote%' THEN 'remote'
                   WHEN COALESCE(location, '') = '' THEN 'location_not_listed'
                   ELSE 'other_us'
               END AS location_bucket,
    first_seen_at,
    last_seen_at,
    job_url
FROM base;

CREATE UNIQUE INDEX IF NOT EXISTS uq_dashboard_jobs_fast_job
    ON jobpush.dashboard_jobs_fast(site_id, external_job_id);
CREATE INDEX IF NOT EXISTS idx_dashboard_jobs_fast_company
    ON jobpush.dashboard_jobs_fast(consolidation_key, first_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_dashboard_jobs_fast_filters
    ON jobpush.dashboard_jobs_fast(priority_tier, role_status, first_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_dashboard_jobs_fast_role_family
    ON jobpush.dashboard_jobs_fast(role_family, first_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_dashboard_jobs_fast_role_stack
    ON jobpush.dashboard_jobs_fast(role_stack, first_seen_at DESC);

COMMIT;

SELECT count(*) AS dashboard_jobs_fast_rows FROM jobpush.dashboard_jobs_fast;
