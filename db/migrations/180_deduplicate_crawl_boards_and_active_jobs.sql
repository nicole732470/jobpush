BEGIN;

-- One ATS board can be attached to several legal entities within the same
-- corporate group. Schedule the board once globally, choosing the strongest
-- active company/site record as its representative.
CREATE OR REPLACE VIEW jobpush.crawl_schedule_queue AS
WITH candidates AS (
  SELECT target.priority_tier,target.priority_score,target.consolidation_key,
         target.canonical_name,site.*,
         CASE
           WHEN site.source_type IN ('greenhouse','lever','ashby','smartrecruiters','workable')
             THEN site.source_type || ':' || lower(coalesce(nullif(site.source_key,''),site.site_url))
           WHEN site.source_type IN (
             'workday','icims','oracle_cloud','rippling','ultipro','paylocity',
             'jobvite','jobscore','applicantpro','dover','catsone','trakstar',
             'breezy','applytojob','phenom','comeet','brassring','eightfold','gusto'
           ) THEN site.source_type || ':' || lower(coalesce(site.normalized_domain,'')) || ':' ||
                  lower(coalesce(nullif(site.source_key,''),site.site_url))
           ELSE site.source_type || ':' || lower(regexp_replace(site.site_url,'[?#].*$',''))
         END AS board_identity
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING(consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P0','P1','P2','P3')
    AND site.verification_status='verified' AND site.crawl_enabled
    AND site.target_country_code='US' AND site.scope_method<>'unknown'
    AND site.source_type IN (
      'amazon_jobs','apple_jobs','cognizant_jobs','eightfold','generic_html',
      'google_jobs','greenhouse','icims','oracle_cloud','workday','lever',
      'ashby','smartrecruiters','workable','jobvite','paylocity','rippling',
      'ultipro','jobscore','applicantpro','dover','catsone','trakstar',
      'breezy','applytojob','phenom','comeet','brassring','gusto'
    )
), ranked AS (
  SELECT candidates.*,
         row_number() OVER (
           PARTITION BY board_identity
           ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 ELSE 3 END,
                    priority_score DESC NULLS LAST,
                    (last_success_at IS NOT NULL) DESC,last_success_at DESC NULLS LAST,site_id
         ) AS board_rank
  FROM candidates
)
SELECT priority_tier,priority_score,consolidation_key,canonical_name,site_id,
       source_type,site_url,scope_method,
       CASE priority_tier WHEN 'P0' THEN 24 WHEN 'P1' THEN 48 WHEN 'P2' THEN 96 WHEN 'P3' THEN 168 END AS recommended_interval_hours,
       last_crawled_at,last_success_at,next_crawl_at,
       coalesce(next_crawl_at,now())<=now() AS is_due,
       consecutive_failures,crawl_status
FROM ranked WHERE board_rank=1;

-- Hide historical cross-site duplicates immediately. Raw rows remain for
-- audit and can still be closed by their source-specific crawl history.
CREATE OR REPLACE VIEW jobpush.job_postings_us AS
WITH ranked AS (
  SELECT posting.*,
         row_number() OVER (
           PARTITION BY posting.job_url
           ORDER BY (site.verification_status='verified' AND site.crawl_enabled) DESC,
                    target.priority_score DESC NULLS LAST,
                    posting.first_seen_at,posting.site_id,posting.external_job_id
         ) AS url_rank
  FROM jobpush.job_postings posting
  JOIN jobpush.career_sites site USING(site_id)
  JOIN jobpush.crawl_targets target ON target.consolidation_key=posting.consolidation_key
  WHERE posting.active AND posting.market_scope='US'
    AND jobpush.posting_is_current_year(posting.posted_text)
)
SELECT site_id,external_job_id,consolidation_key,title,normalized_title,location,
       category,job_url,description_snippet,active,first_seen_at,last_seen_at,
       closed_at,last_run_id,updated_at,market_scope,posted_text,employment_type
FROM ranked WHERE url_rank=1;

COMMIT;

SELECT
  (SELECT count(*) FROM jobpush.career_sites site JOIN jobpush.crawl_targets target USING(consolidation_key)
   WHERE target.enabled AND site.verification_status='verified' AND site.crawl_enabled) AS enabled_site_rows,
  (SELECT count(*) FROM jobpush.crawl_schedule_queue) AS unique_scheduled_boards,
  (SELECT count(*) FROM jobpush.job_postings WHERE active AND market_scope='US') AS raw_active_us_rows,
  (SELECT count(*) FROM jobpush.job_postings_us) AS unique_active_us_urls;
