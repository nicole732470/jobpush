BEGIN;

-- Parse only conservative fields from the 20-row pilot. The original answer
-- and sources remain authoritative audit evidence; parsed values stay
-- unreviewed and cannot affect production scoring.
WITH parsed AS (
    SELECT
        consolidation_key,
        (regexp_match(lower(company_description), 'founded in ([12][0-9]{3})'))[1]::INTEGER
            AS parsed_founded_year,
        (regexp_match(lower(company_description),
          '(?:(?:with|has|employs)[[:space:]]+)?(?:over|around|approximately|about)?[[:space:]]*([0-9][0-9,]*)\+?[[:space:]]+(?:employees|people)'))[1]
            AS parsed_employee_count,
        coalesce(
            (regexp_match(company_description, '(?i)primary industry is ([^.]+)'))[1],
            (regexp_match(company_description, '(?i)operates in the ([^,.]+) industry'))[1],
            (regexp_match(company_description, '(?i)in the ([^,.]+) industry'))[1]
        ) AS parsed_industry,
        trim(trailing ', ' FROM regexp_replace(regexp_replace(
            (regexp_match(company_description,
              '(?i)headquartered in ([^,.]+(?:, [^,.]+)?)'))[1],
            '(?i)[[:space:]]+(with|and)[[:space:]].*$', ''),
          '(?i),?[[:space:]]*founded in.*$', '')) AS parsed_headquarters,
        CASE
            WHEN lower(company_description) ~ '\bnonprofit\b' THEN 'nonprofit'
            WHEN lower(company_description) ~ '\bpublic(ly)? ([a-z]+ ){0,3}(company|owned)\b' THEN 'public'
            WHEN lower(company_description) ~ '\bprivate(ly)? ([a-z]+ ){0,3}(company|owned)\b' THEN 'private'
        END AS parsed_ownership,
        (regexp_match(company_description,
          '(?i)official website is (www\.)?([a-z0-9.-]+\.[a-z]{2,})'))[2]
            AS parsed_website
    FROM jobpush.company_external_enrichment
    WHERE extraction_method IN ('tavily-basic-answer-v1', 'tavily-basic-answer-regex-v1')
      AND company_description IS NOT NULL
)
UPDATE jobpush.company_external_enrichment enrichment
SET
    founded_year = coalesce(enrichment.founded_year, parsed.parsed_founded_year),
    employee_count_min = coalesce(
        enrichment.employee_count_min,
        replace(parsed.parsed_employee_count, ',', '')::INTEGER
    ),
    industry = coalesce(enrichment.industry, nullif(trim(parsed.parsed_industry), '')),
    headquarters_city = CASE
        WHEN length(trim(parsed.parsed_headquarters)) >= 5
          AND lower(trim(parsed.parsed_headquarters)) NOT IN ('the u', 'the us')
        THEN nullif(trim(parsed.parsed_headquarters), '')
        ELSE NULL
    END,
    ownership_type = coalesce(enrichment.ownership_type, parsed.parsed_ownership),
    official_website_url = coalesce(
        enrichment.official_website_url,
        CASE WHEN parsed.parsed_website IS NOT NULL
             THEN 'https://' || parsed.parsed_website END
    ),
    extraction_method = 'tavily-basic-answer-regex-v1',
    confidence = 0.650,
    updated_at = now()
FROM parsed
WHERE enrichment.consolidation_key = parsed.consolidation_key;

DROP VIEW IF EXISTS jobpush.company_priority_enrichment_workbench;

CREATE VIEW jobpush.company_priority_enrichment_workbench AS
SELECT
    target.*,
    CASE
        WHEN enrichment.consolidation_key IS NULL THEN 'not_researched'
        WHEN enrichment.industry IS NOT NULL
          OR enrichment.employee_count_min IS NOT NULL
          OR enrichment.headquarters_city IS NOT NULL
          OR enrichment.founded_year IS NOT NULL
          OR enrichment.ownership_type IS NOT NULL
          THEN 'structured_unreviewed'
        ELSE 'researched_unstructured'
    END AS enrichment_state,
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

COMMENT ON VIEW jobpush.company_priority_enrichment_workbench IS
    'Priority analysis with explicit enrichment_state. Filter enrichment_state <> not_researched to inspect Tavily company profiles.';

COMMIT;
