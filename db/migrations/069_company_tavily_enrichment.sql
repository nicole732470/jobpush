BEGIN;

-- Durable, source-attributed company attributes.  This table deliberately
-- lives outside the LCA fact tables: web research is mutable and may be wrong.
CREATE TABLE IF NOT EXISTS jobpush.company_external_enrichment (
    consolidation_key TEXT PRIMARY KEY
        REFERENCES jobpush.crawl_targets(consolidation_key)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    official_website_url TEXT,
    industry TEXT,
    industry_detail TEXT,
    headquarters_city TEXT,
    headquarters_state TEXT,
    headquarters_country TEXT,
    employee_count_min INTEGER,
    employee_count_max INTEGER,
    founded_year INTEGER,
    ownership_type TEXT,
    company_description TEXT,
    source_urls TEXT[] NOT NULL DEFAULT '{}',
    source_provider TEXT NOT NULL DEFAULT 'tavily',
    source_query TEXT,
    raw_response JSONB,
    extraction_method TEXT NOT NULL DEFAULT 'unreviewed',
    confidence NUMERIC(4, 3),
    review_status TEXT NOT NULL DEFAULT 'unreviewed',
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    researched_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT company_external_enrichment_employee_range_check CHECK (
        employee_count_min IS NULL OR employee_count_max IS NULL
        OR employee_count_min <= employee_count_max
    ),
    CONSTRAINT company_external_enrichment_founded_year_check CHECK (
        founded_year IS NULL OR founded_year BETWEEN 1600 AND 2100
    ),
    CONSTRAINT company_external_enrichment_confidence_check CHECK (
        confidence IS NULL OR confidence BETWEEN 0 AND 1
    ),
    CONSTRAINT company_external_enrichment_review_status_check CHECK (
        review_status IN ('unreviewed', 'verified', 'rejected', 'conflicting')
    )
);

CREATE INDEX IF NOT EXISTS idx_company_external_enrichment_industry
    ON jobpush.company_external_enrichment(industry)
    WHERE review_status = 'verified';

CREATE INDEX IF NOT EXISTS idx_company_external_enrichment_research
    ON jobpush.company_external_enrichment(review_status, researched_at);

-- Zero-credit features recovered from the Tavily career-site searches that
-- were already persisted.  Tavily's discarded full response cannot be
-- reconstructed; these are the source-backed fields we actually retained.
CREATE OR REPLACE VIEW jobpush.company_tavily_discovery_features AS
WITH tavily_sites AS (
    SELECT
        site.*,
        row_number() OVER (
            PARTITION BY site.consolidation_key
            ORDER BY site.candidate_rank NULLS LAST,
                     site.candidate_score DESC NULLS LAST,
                     site.site_id
        ) AS retained_rank
    FROM jobpush.career_sites site
    WHERE site.discovery_source = 'tavily_basic'
), aggregated AS (
    SELECT
        target.consolidation_key,
        target.last_discovery_at IS NOT NULL AS tavily_searched,
        target.last_discovery_at AS tavily_last_searched_at,
        count(site.site_id)::INTEGER AS retained_candidate_count,
        count(site.site_id) FILTER (
            WHERE site.source_type <> 'generic_html'
        )::INTEGER AS structured_ats_candidate_count,
        count(site.site_id) FILTER (
            WHERE site.verification_status = 'verified'
        )::INTEGER AS verified_candidate_count,
        bool_or(site.last_success_at IS NOT NULL) AS has_successful_crawl,
        max(site.candidate_score) AS best_candidate_score,
        array_remove(array_agg(DISTINCT site.source_type), NULL) AS candidate_source_types,
        max(site.site_url) FILTER (WHERE site.retained_rank = 1) AS rank1_site_url,
        max(site.normalized_domain) FILTER (WHERE site.retained_rank = 1) AS rank1_domain,
        max(site.source_type) FILTER (WHERE site.retained_rank = 1) AS rank1_source_type,
        max(site.evidence_title) FILTER (WHERE site.retained_rank = 1) AS rank1_evidence_title,
        max(site.evidence_snippet) FILTER (WHERE site.retained_rank = 1) AS rank1_evidence_snippet
    FROM jobpush.crawl_targets target
    LEFT JOIN tavily_sites site USING (consolidation_key)
    GROUP BY target.consolidation_key, target.last_discovery_at
)
SELECT * FROM aggregated;

-- One analysis surface: current priority facts + retained Tavily discovery
-- evidence + optional researched company attributes.
CREATE OR REPLACE VIEW jobpush.company_priority_enrichment_workbench AS
SELECT
    target.*,
    feature.tavily_searched,
    feature.tavily_last_searched_at,
    feature.retained_candidate_count,
    feature.structured_ats_candidate_count,
    feature.verified_candidate_count,
    feature.has_successful_crawl,
    feature.best_candidate_score,
    feature.candidate_source_types,
    feature.rank1_site_url,
    feature.rank1_domain,
    feature.rank1_source_type,
    feature.rank1_evidence_title,
    feature.rank1_evidence_snippet,
    enrichment.official_website_url,
    enrichment.industry AS external_industry,
    enrichment.industry_detail AS external_industry_detail,
    enrichment.headquarters_city AS external_headquarters_city,
    enrichment.headquarters_state AS external_headquarters_state,
    enrichment.headquarters_country AS external_headquarters_country,
    enrichment.employee_count_min,
    enrichment.employee_count_max,
    enrichment.founded_year,
    enrichment.ownership_type,
    enrichment.company_description,
    enrichment.source_urls AS enrichment_source_urls,
    enrichment.confidence AS enrichment_confidence,
    enrichment.review_status AS enrichment_review_status,
    enrichment.researched_at AS enrichment_researched_at
FROM jobpush.company_targets_consolidated target
LEFT JOIN jobpush.company_tavily_discovery_features feature USING (consolidation_key)
LEFT JOIN jobpush.company_external_enrichment enrichment USING (consolidation_key);

COMMENT ON TABLE jobpush.company_external_enrichment IS
    'Mutable, source-attributed external company profile. Only verified attributes may be used in production priority scoring.';
COMMENT ON VIEW jobpush.company_tavily_discovery_features IS
    'Zero-credit company features reconstructed from retained Tavily career-site candidate evidence.';
COMMENT ON VIEW jobpush.company_priority_enrichment_workbench IS
    'Company priority analysis surface joining LCA-derived facts, retained Tavily discovery evidence, and optional external enrichment.';

COMMIT;
