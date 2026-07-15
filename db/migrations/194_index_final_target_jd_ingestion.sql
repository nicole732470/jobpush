CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dashboard_jobs_fast_final_target_keys
  ON jobpush.dashboard_jobs_fast(site_id,external_job_id)
  WHERE role_status = 'target';
