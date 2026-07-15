BEGIN;

CREATE OR REPLACE FUNCTION jobpush.is_explicit_no_sponsorship(description TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(description, '') ~* '((unable|cannot|can not|will not|do not|does not|not able to|no longer).{0,80}(sponsor|sponsorship)|(no|without).{0,50}(visa|employment|work authorization).{0,50}sponsorship|(visa|employment|work authorization).{0,50}sponsorship.{0,40}(not available|unavailable|not provided)|must.{0,80}(authorized|eligible).{0,100}without.{0,50}sponsorship|not.{0,30}eligible.{0,50}(visa )?sponsorship|sponsorship.{0,40}(is )?not (available|offered|provided))'
$$;

CREATE OR REPLACE VIEW jobpush.dashboard_jobs AS
SELECT
    posting.site_id, posting.external_job_id, posting.consolidation_key,
    target.canonical_name, target.priority_tier, posting.title, posting.normalized_title,
    posting.location, posting.category, posting.employment_type,
    CASE
        WHEN ((posting.title ILIKE '%%c++%%' OR posting.title ILIKE '%%c#%%'
               OR posting.title ILIKE '%%.net/c#%%' OR posting.title ILIKE '%%c#/.net%%')
              AND (posting.title ILIKE '%%software%%' OR posting.title ILIKE '%%developer%%'
                   OR posting.title ILIKE '%%engineer%%' OR posting.title ILIKE '%%full stack%%'
                   OR posting.title ILIKE '%%full-stack%%' OR posting.title ILIKE '%%backend%%'
                   OR posting.title ILIKE '%%frontend%%' OR posting.title ILIKE '%%sdet%%'))
             OR posting.title ~* '(^|[^a-z0-9])c (software engineer|developer|programmer)([^a-z0-9]|$)'
          THEN 'non_target'
        WHEN snapshot.scrape_status = 'succeeded'
             AND jobpush.is_explicit_no_sponsorship(snapshot.cleaned_description) THEN 'non_target'
        WHEN snapshot.scrape_status = 'succeeded' THEN COALESCE(label.classification_status, 'review')
        ELSE 'review'
    END AS role_status,
    CASE WHEN snapshot.scrape_status = 'succeeded'
              AND NOT (((posting.title ILIKE '%%c++%%' OR posting.title ILIKE '%%c#%%'
                         OR posting.title ILIKE '%%.net/c#%%' OR posting.title ILIKE '%%c#/.net%%')
                        AND (posting.title ILIKE '%%software%%' OR posting.title ILIKE '%%developer%%'
                             OR posting.title ILIKE '%%engineer%%' OR posting.title ILIKE '%%full stack%%'
                             OR posting.title ILIKE '%%full-stack%%' OR posting.title ILIKE '%%backend%%'
                             OR posting.title ILIKE '%%frontend%%' OR posting.title ILIKE '%%sdet%%'))
                       OR posting.title ~* '(^|[^a-z0-9])c (software engineer|developer|programmer)([^a-z0-9]|$)')
              AND NOT jobpush.is_explicit_no_sponsorship(snapshot.cleaned_description)
         THEN label.canonical_role ELSE NULL END AS canonical_role,
    COALESCE(action.action_status, 'new') AS application_status,
    action.notes AS application_notes, posting.posted_text, posting.first_seen_at,
    posting.last_seen_at, posting.job_url
FROM jobpush.job_postings_us posting
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
LEFT JOIN jobpush.job_description_snapshots snapshot
  ON snapshot.site_id = posting.site_id AND snapshot.external_job_id = posting.external_job_id
 AND snapshot.source_fingerprint = md5(concat_ws(E'\x1f','jd-v2-complete-content',posting.title,posting.location,
       posting.category,posting.job_url,posting.description_snippet,posting.posted_text,posting.employment_type))
LEFT JOIN jobpush.job_application_actions action
  ON action.site_id = posting.site_id AND action.external_job_id = posting.external_job_id;

COMMIT;
