CREATE OR REPLACE VIEW jobpush.company_identity_search AS
WITH member_feins AS (
    SELECT target.consolidation_key,
           target.canonical_name,
           unnest(consolidated.member_feins) AS fein
    FROM jobpush.crawl_targets target
    JOIN jobpush.company_targets_consolidated consolidated USING (consolidation_key)
    WHERE target.enabled
), raw_terms AS (
    SELECT consolidation_key, canonical_name AS term, 0 AS priority
    FROM member_feins
    UNION ALL
    SELECT member.consolidation_key, company.name, 1
    FROM member_feins member
    JOIN public.companies company ON company.fein = member.fein
    UNION ALL
    SELECT member.consolidation_key, alias.alias_name, 1
    FROM member_feins member
    JOIN public.company_aliases alias ON alias.fein = member.fein
    UNION ALL
    SELECT member.consolidation_key, replace(search.search_key, '-', ' '), 2
    FROM member_feins member
    JOIN public.company_search_keys search ON search.fein = member.fein
), cleaned_terms AS (
    SELECT DISTINCT ON (consolidation_key, lower(term))
           consolidation_key,
           btrim(term) AS term,
           priority
    FROM raw_terms
    WHERE btrim(COALESCE(term, '')) <> ''
      AND length(btrim(term)) >= 3
    ORDER BY consolidation_key, lower(term), priority, length(term)
), acronym_terms AS (
    SELECT DISTINCT consolidation_key, acronym AS term, priority
    FROM (
        SELECT cleaned.consolidation_key,
               cleaned.priority,
               upper(string_agg(left(part.word, 1), '' ORDER BY part.ord)) AS acronym
        FROM cleaned_terms cleaned
        CROSS JOIN LATERAL regexp_split_to_table(
            regexp_replace(
                cleaned.term,
                '\m(the|incorporated|inc|llc|ltd|lp|llp|corp|corporation|company|co)\M',
                ' ',
                'gi'
            ),
            '[^[:alnum:]]+'
        ) WITH ORDINALITY AS part(word, ord)
        WHERE part.word <> ''
          AND length(part.word) > 1
        GROUP BY cleaned.consolidation_key, cleaned.term, cleaned.priority
    ) acronyms
    WHERE length(acronym) BETWEEN 2 AND 8
), final_terms AS (
    SELECT consolidation_key, term, priority FROM cleaned_terms
    UNION ALL
    SELECT consolidation_key, term, priority FROM acronym_terms
)
SELECT target.consolidation_key,
       target.canonical_name,
       string_agg(final_terms.term, ' ' ORDER BY final_terms.priority, length(final_terms.term), final_terms.term) AS search_text,
       array_agg(final_terms.term ORDER BY final_terms.priority, length(final_terms.term), final_terms.term)
           FILTER (WHERE final_terms.priority <= 1) AS tavily_search_terms
FROM jobpush.crawl_targets target
LEFT JOIN final_terms USING (consolidation_key)
WHERE target.enabled
GROUP BY target.consolidation_key, target.canonical_name;

SELECT jobpush.set_manual_crawl_priority(
    '04-2432614',
    'P0',
    'Nicole confirmed BCG as manual P0 on 2026-07-07'
);

INSERT INTO jobpush.career_sites (
    consolidation_key,
    site_url,
    normalized_domain,
    site_kind,
    source_type,
    source_key,
    discovery_source,
    verification_status,
    crawl_enabled,
    crawl_status,
    target_country_code,
    scope_method,
    crawl_interval_hours,
    next_crawl_at,
    reviewed_at,
    reviewed_by,
    review_notes,
    updated_at
) VALUES (
    '04-2432614',
    'https://careers.bcg.com/global/en/search-results',
    'careers.bcg.com',
    'careers',
    'generic_html',
    NULL,
    'manual_dashboard',
    'verified',
    TRUE,
    'pending',
    'US',
    'local_filter',
    24,
    now(),
    now(),
    'nicole',
    'Nicole confirmed BCG official careers site. No URL-level US filter; keep only explicit US postings via local market_scope filter.',
    now()
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    crawl_interval_hours = 24,
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = EXCLUDED.review_notes,
    updated_at = now();

UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'pending',
    review_notes = 'Superseded by Nicole confirmed BCG canonical careers URL on 2026-07-07.',
    updated_at = now()
WHERE consolidation_key = '04-2432614'
  AND normalized_domain = 'careers.bcg.com'
  AND site_url <> 'https://careers.bcg.com/global/en/search-results';
