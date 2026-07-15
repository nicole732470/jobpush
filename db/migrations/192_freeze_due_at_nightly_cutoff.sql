BEGIN;

CREATE OR REPLACE FUNCTION jobpush.crawl_batch_cutoff(p_now TIMESTAMPTZ DEFAULT now())
RETURNS TIMESTAMPTZ
LANGUAGE sql
STABLE
AS $$
  WITH local_clock AS (
    SELECT p_now AT TIME ZONE 'America/Chicago' AS local_now
  )
  SELECT (
    date_trunc('day', local_now) +
    CASE WHEN local_now::time >= time '01:00'
         THEN interval '1 hour' ELSE interval '-23 hours' END
  ) AT TIME ZONE 'America/Chicago'
  FROM local_clock
$$;

DO $$
BEGIN
  IF jobpush.crawl_batch_cutoff('2026-07-15 05:59:00+00') <> '2026-07-14 06:00:00+00' THEN
    RAISE EXCEPTION 'pre-1am cutoff must remain on the previous nightly batch';
  END IF;
  IF jobpush.crawl_batch_cutoff('2026-07-15 06:00:00+00') <> '2026-07-15 06:00:00+00' THEN
    RAISE EXCEPTION '1am cutoff must open the new nightly batch';
  END IF;
END;
$$;

CREATE OR REPLACE VIEW jobpush.crawl_schedule_queue AS
WITH candidates AS (
  SELECT target.priority_tier,target.priority_score,target.canonical_name,site.*,
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
SELECT ranked.priority_tier,ranked.priority_score,ranked.consolidation_key,ranked.canonical_name,ranked.site_id,
       ranked.source_type,ranked.site_url,ranked.scope_method,
       CASE ranked.priority_tier WHEN 'P0' THEN 24 WHEN 'P1' THEN 48 WHEN 'P2' THEN 96 WHEN 'P3' THEN 168 END AS recommended_interval_hours,
       ranked.last_crawled_at,ranked.last_success_at,ranked.next_crawl_at,
       coalesce(ranked.next_crawl_at,now())<=jobpush.crawl_batch_cutoff(now()) AS is_due,
       ranked.consecutive_failures,ranked.crawl_status
FROM ranked WHERE ranked.board_rank=1;

COMMIT;
