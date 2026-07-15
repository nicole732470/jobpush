-- Supports the URL-partitioned active-job view without locking writes.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_job_postings_active_us_job_url
ON jobpush.job_postings(job_url,first_seen_at,site_id,external_job_id)
WHERE active AND market_scope='US';

ANALYZE jobpush.job_postings;
