BEGIN;

ALTER TABLE jobpush.career_sites
    ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reviewed_by TEXT,
    ADD COLUMN IF NOT EXISTS review_notes TEXT;

CREATE TABLE IF NOT EXISTS jobpush.career_site_discovery_domain_excludes (
    domain TEXT PRIMARY KEY,
    reason TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO jobpush.career_site_discovery_domain_excludes (domain, reason)
VALUES
    ('linkedin.com', 'job aggregator or social platform'),
    ('indeed.com', 'job aggregator'),
    ('glassdoor.com', 'job aggregator'),
    ('ziprecruiter.com', 'job aggregator'),
    ('builtin.com', 'job aggregator'),
    ('builtinchicago.org', 'job aggregator'),
    ('builtinnyc.com', 'job aggregator'),
    ('naukri.com', 'job aggregator'),
    ('virtualvocations.com', 'job aggregator'),
    ('flexjobs.com', 'job aggregator'),
    ('career.com', 'job aggregator'),
    ('instahyre.com', 'job aggregator'),
    ('remoterocketship.com', 'job aggregator'),
    ('levels.fyi', 'company profile aggregator'),
    ('dice.com', 'job aggregator'),
    ('latinograduate.com', 'job aggregator'),
    ('hirebase.org', 'job aggregator'),
    ('6amcity.com', 'job aggregator'),
    ('insidehighered.com', 'external industry job board'),
    ('nena.org', 'external industry job board'),
    ('acams.org', 'external industry job board')
ON CONFLICT (domain) DO UPDATE SET
    reason = EXCLUDED.reason,
    active = TRUE;

DELETE FROM jobpush.career_sites site
WHERE site.verification_status = 'unverified'
  AND site.discovery_source = 'tavily_basic'
  AND EXISTS (
      SELECT 1
      FROM jobpush.career_site_discovery_domain_excludes excluded
      WHERE excluded.active
        AND (
            site.normalized_domain = excluded.domain
            OR site.normalized_domain LIKE '%.' || excluded.domain
        )
  );

UPDATE jobpush.crawl_targets target
SET
    discovery_status = 'not_found',
    next_discovery_at = now() + INTERVAL '30 days',
    updated_at = now()
WHERE target.discovery_status = 'review_pending'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.verification_status IN ('unverified', 'verified')
  );

CREATE OR REPLACE VIEW jobpush.career_site_review_queue AS
SELECT
    site.site_id,
    target.consolidation_key,
    target.canonical_name,
    target.priority_tier,
    target.priority_score,
    site.candidate_rank,
    site.candidate_score,
    site.source_type,
    site.site_kind,
    site.site_url,
    site.evidence_title,
    site.evidence_snippet,
    site.verification_status,
    COUNT(*) OVER (PARTITION BY site.consolidation_key) AS company_candidate_count,
    site.last_discovered_at
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target
  ON target.consolidation_key = site.consolidation_key
WHERE site.verification_status = 'unverified'
  AND target.discovery_status = 'review_pending';

CREATE OR REPLACE VIEW jobpush.career_site_company_review_queue AS
SELECT
    target.consolidation_key,
    target.canonical_name,
    target.priority_tier,
    target.priority_score,
    COUNT(site.site_id) AS candidate_count,
    MAX(site.site_id) FILTER (WHERE site.candidate_rank = 1) AS candidate_1_site_id,
    MAX(site.site_url) FILTER (WHERE site.candidate_rank = 1) AS candidate_1_url,
    MAX(site.source_type) FILTER (WHERE site.candidate_rank = 1) AS candidate_1_source,
    MAX(site.evidence_title) FILTER (WHERE site.candidate_rank = 1) AS candidate_1_title,
    MAX(site.site_id) FILTER (WHERE site.candidate_rank = 2) AS candidate_2_site_id,
    MAX(site.site_url) FILTER (WHERE site.candidate_rank = 2) AS candidate_2_url,
    MAX(site.source_type) FILTER (WHERE site.candidate_rank = 2) AS candidate_2_source,
    MAX(site.evidence_title) FILTER (WHERE site.candidate_rank = 2) AS candidate_2_title,
    MAX(site.site_id) FILTER (WHERE site.candidate_rank = 3) AS candidate_3_site_id,
    MAX(site.site_url) FILTER (WHERE site.candidate_rank = 3) AS candidate_3_url,
    MAX(site.source_type) FILTER (WHERE site.candidate_rank = 3) AS candidate_3_source,
    MAX(site.evidence_title) FILTER (WHERE site.candidate_rank = 3) AS candidate_3_title
FROM jobpush.crawl_targets target
JOIN jobpush.career_sites site
  ON site.consolidation_key = target.consolidation_key
 AND site.verification_status = 'unverified'
WHERE target.discovery_status = 'review_pending'
GROUP BY
    target.consolidation_key,
    target.canonical_name,
    target.priority_tier,
    target.priority_score;

CREATE OR REPLACE FUNCTION jobpush.review_career_site(
    p_site_id BIGINT,
    p_decision TEXT,
    p_reviewed_by TEXT DEFAULT 'nicole',
    p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    company_key TEXT;
BEGIN
    IF p_decision NOT IN ('verified', 'rejected') THEN
        RAISE EXCEPTION 'Decision must be verified or rejected';
    END IF;

    UPDATE jobpush.career_sites
    SET
        verification_status = p_decision,
        crawl_enabled = (p_decision = 'verified'),
        crawl_status = 'pending',
        next_crawl_at = CASE WHEN p_decision = 'verified' THEN now() ELSE NULL END,
        reviewed_at = now(),
        reviewed_by = NULLIF(BTRIM(p_reviewed_by), ''),
        review_notes = p_notes,
        updated_at = now()
    WHERE site_id = p_site_id
    RETURNING consolidation_key INTO company_key;

    IF company_key IS NULL THEN
        RAISE EXCEPTION 'Career site % does not exist', p_site_id;
    END IF;

    UPDATE jobpush.crawl_targets target
    SET
        discovery_status = CASE
            WHEN EXISTS (
                SELECT 1 FROM jobpush.career_sites site
                WHERE site.consolidation_key = company_key
                  AND site.verification_status = 'verified'
            ) THEN 'found'
            WHEN EXISTS (
                SELECT 1 FROM jobpush.career_sites site
                WHERE site.consolidation_key = company_key
                  AND site.verification_status = 'unverified'
            ) THEN 'review_pending'
            ELSE 'not_found'
        END,
        next_discovery_at = CASE
            WHEN EXISTS (
                SELECT 1 FROM jobpush.career_sites site
                WHERE site.consolidation_key = company_key
                  AND site.verification_status IN ('verified', 'unverified')
            ) THEN NULL
            ELSE now() + INTERVAL '30 days'
        END,
        updated_at = now()
    WHERE target.consolidation_key = company_key;
END;
$$;

COMMIT;
