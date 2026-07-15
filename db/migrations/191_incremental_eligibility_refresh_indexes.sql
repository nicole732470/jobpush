CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_job_description_snapshots_updated_at
  ON jobpush.job_description_snapshots(updated_at,site_id,external_job_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_job_title_labels_updated_at
  ON jobpush.job_title_labels(updated_at,normalized_title);
