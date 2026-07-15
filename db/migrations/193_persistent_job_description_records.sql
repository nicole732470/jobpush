BEGIN;

ALTER TABLE jobpush.job_description_snapshots
  ADD COLUMN IF NOT EXISTS parser_version TEXT NOT NULL DEFAULT 'unknown';

COMMENT ON TABLE jobpush.job_description_snapshots IS
  'Persistent raw and cleaned job-description snapshots. Independent of JSON export and email delivery.';
COMMENT ON COLUMN jobpush.job_description_snapshots.raw_html IS
  'Original response body retained so improved parsers can reprocess it without another request.';
COMMENT ON COLUMN jobpush.job_description_snapshots.cleaned_description IS
  'Complete cleaned job description; never a summary or ranking.';
COMMENT ON COLUMN jobpush.job_description_snapshots.parser_version IS
  'Parser version that produced the current cleaned and structured fields.';

CREATE OR REPLACE VIEW jobpush.job_description_records AS
SELECT
  snapshot.site_id,
  snapshot.external_job_id,
  posting.consolidation_key,
  target.canonical_name AS company,
  posting.title,
  posting.normalized_title,
  posting.location,
  snapshot.work_arrangement,
  posting.employment_type,
  snapshot.salary_text,
  snapshot.posted_date,
  posting.posted_text,
  posting.first_seen_at,
  posting.last_seen_at,
  posting.closed_at,
  posting.active,
  posting.market_scope,
  posting.job_url,
  snapshot.apply_url,
  site.source_type,
  site.source_key,
  label.classification_status AS title_classification_status,
  label.canonical_role,
  label.rule_version AS classification_rule_version,
  label.decision_reason AS classification_reason,
  snapshot.cleaned_description AS complete_job_description,
  snapshot.raw_html,
  snapshot.content_type,
  snapshot.source_fingerprint,
  snapshot.parser_version,
  snapshot.scrape_status,
  snapshot.scrape_error,
  snapshot.http_status,
  snapshot.attempt_count,
  snapshot.scraped_at,
  snapshot.updated_at
FROM jobpush.job_description_snapshots snapshot
JOIN jobpush.job_postings posting USING (site_id, external_job_id)
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target ON target.consolidation_key = posting.consolidation_key
LEFT JOIN jobpush.job_title_labels label USING (normalized_title);

COMMENT ON VIEW jobpush.job_description_records IS
  'Stable analysis interface for job metadata, complete cleaned JD, raw HTML, classification context, and scrape metadata.';

COMMIT;
