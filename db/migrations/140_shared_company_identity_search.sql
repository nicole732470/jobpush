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
)
SELECT target.consolidation_key,
       target.canonical_name,
       string_agg(cleaned.term, ' ' ORDER BY cleaned.priority, length(cleaned.term), cleaned.term) AS search_text,
       array_agg(cleaned.term ORDER BY cleaned.priority, length(cleaned.term), cleaned.term)
           FILTER (WHERE cleaned.priority <= 1) AS tavily_search_terms
FROM jobpush.crawl_targets target
LEFT JOIN cleaned_terms cleaned USING (consolidation_key)
WHERE target.enabled
GROUP BY target.consolidation_key, target.canonical_name;
