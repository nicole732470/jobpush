BEGIN;

CREATE OR REPLACE FUNCTION jobpush.title_review_cluster_key(p_title TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_title TEXT := lower(coalesce(p_title, ''));
    v_token TEXT;
    v_tokens TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF v_title ~ '(^|[^a-z])(dentist|dental|orthodont|oral surgeon|endodontist|periodontist)([^a-z]|$)' THEN
        RETURN 'svc:dental';
    ELSIF v_title ~ '(^|[^a-z])(barista|cafe|café|restaurant|server|cook|dishwasher|kitchen|food runner|busser|hostess)([^a-z]|$)' THEN
        RETURN 'svc:food_restaurant';
    ELSIF v_title ~ '(^|[^a-z])(cashier|shopper|shopping|store associate|retail associate|sales floor|cart attendant|stocker|merchandise associate)([^a-z]|$)' THEN
        RETURN 'svc:retail_store';
    ELSIF v_title ~ '(^|[^a-z])(courier|carrier|delivery driver|route driver|package handler|cdl driver|truck driver|forklift)([^a-z]|$)' THEN
        RETURN 'svc:delivery_logistics';
    ELSIF v_title ~ '(^|[^a-z])(security officer|security guard|valet|bus monitor|direct support professional|care worker|caregiver)([^a-z]|$)' THEN
        RETURN 'svc:frontline_care_security';
    ELSIF v_title ~ '(^|[^a-z])(nurse|nursing|physician|therapist|medical assistant|clinical|microbiologist|resident -?pgy|chaplain|medical records)([^a-z]|$)' THEN
        RETURN 'clinical:healthcare';
    ELSIF v_title ~ '(^|[^a-z])(teacher|teaching|instructor|professor|faculty|tutor|school)([^a-z]|$)' THEN
        RETURN 'edu:teaching';
    ELSIF v_title ~ '(^|[^a-z])(attorney|lawyer|legal|paralegal|litigation|counsel)([^a-z]|$)' THEN
        RETURN 'legal:legal';
    ELSIF v_title ~ '(^|[^a-z])(cleaner|cleaning|janitor|housekeeper|sanitation)([^a-z]|$)' THEN
        RETURN 'svc:cleaning';
    ELSIF v_title ~ '(^|[^a-z])(mechanic|electrician|plumber|welder|hvac|maintenance|technician|machine operator|plant technician|corrugate)([^a-z]|$)' THEN
        RETURN 'trade:technician_operator';
    ELSIF v_title ~ '(^|[^a-z])(product manager|product owner|product analyst|product marketing)([^a-z]|$)' THEN
        RETURN 'targetish:product';
    ELSIF v_title ~ '(^|[^a-z])(data engineer|data analyst|data scientist|data modeler|business intelligence|bi analyst)([^a-z]|$)' THEN
        RETURN 'targetish:data';
    ELSIF v_title ~ '(^|[^a-z])(software engineer|software developer|developer|programmer|devops|cloud engineer|qa engineer|test engineer)([^a-z]|$)' THEN
        RETURN 'tech:sde_dev';
    ELSIF v_title ~ '(^|[^a-z])(system engineer|systems engineer|solutions engineer|solution architect|solutions architect|sales engineer)([^a-z]|$)' THEN
        RETURN 'targetish:systems_solutions';
    ELSIF v_title ~ '(^|[^a-z])(project manager|program manager|business analyst|systems analyst|implementation)([^a-z]|$)' THEN
        RETURN 'targetish:business_program';
    ELSIF v_title ~ '(^|[^a-z])(architect)([^a-z]|$)' THEN
        RETURN 'boundary:architect';
    ELSIF v_title ~ '(^|[^a-z])(manager|supervisor|director|lead|principal|head|vice president|vp)([^a-z]|$)' THEN
        RETURN 'boundary:seniority_management';
    END IF;

    FOR v_token IN
        SELECT token
        FROM regexp_split_to_table(v_title, '[^a-z0-9+#.]+') AS token
        WHERE length(token) > 2
          AND token NOT IN (
              'and','the','for','with','senior','junior','associate','assistant',
              'manager','specialist','engineer','developer','analyst','consultant',
              'coordinator','administrator','professional','level','remote',
              'full','time','part','shift','contract','intern','internship'
          )
        LIMIT 2
    LOOP
        v_tokens := array_append(v_tokens, v_token);
    END LOOP;

    IF array_length(v_tokens, 1) IS NULL THEN
        RETURN 'other:' || left(regexp_replace(v_title, '[^a-z0-9]+', '_', 'g'), 40);
    END IF;
    RETURN 'token:' || array_to_string(v_tokens, '_');
END;
$$;

CREATE OR REPLACE VIEW jobpush.job_title_cluster_review_queue AS
WITH queue AS (
    SELECT
        jobpush.title_review_cluster_key(normalized_title) AS cluster_key,
        normalized_title,
        example_title,
        active_posting_count,
        company_count,
        suggestion_reason,
        matched_soc_titles
    FROM jobpush.job_title_review_queue
), ranked AS (
    SELECT
        queue.*,
        row_number() OVER (
            PARTITION BY cluster_key
            ORDER BY active_posting_count DESC, company_count DESC, normalized_title
        ) AS example_rank
    FROM queue
)
SELECT
    cluster_key,
    CASE
        WHEN cluster_key LIKE 'svc:%'
          OR cluster_key LIKE 'clinical:%'
          OR cluster_key LIKE 'edu:%'
          OR cluster_key LIKE 'legal:%'
          OR cluster_key LIKE 'trade:%'
            THEN 'likely_non_target'
        WHEN cluster_key LIKE 'targetish:%'
            THEN 'likely_target_or_boundary'
        ELSE 'review'
    END AS cluster_hint,
    count(*) AS title_count,
    sum(active_posting_count)::integer AS active_postings,
    sum(company_count)::integer AS company_mentions,
    string_agg(normalized_title, ' | ' ORDER BY active_posting_count DESC, normalized_title)
        FILTER (WHERE example_rank <= 8) AS example_titles,
    string_agg(DISTINCT NULLIF(matched_soc_titles, ''), ' | ' ORDER BY NULLIF(matched_soc_titles, ''))
        FILTER (WHERE matched_soc_titles IS NOT NULL) AS matched_soc_titles
FROM ranked
GROUP BY cluster_key
ORDER BY
    sum(active_posting_count) DESC,
    count(*) DESC,
    cluster_key;

CREATE OR REPLACE FUNCTION jobpush.apply_manual_job_title_cluster_label(
    p_cluster_key TEXT,
    p_status TEXT,
    p_canonical_role TEXT,
    p_reason TEXT,
    p_labeled_by TEXT DEFAULT 'nicole',
    p_limit INTEGER DEFAULT 5000
) RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER := 0;
    v_title TEXT;
BEGIN
    IF p_status NOT IN ('review', 'target', 'non_target') THEN
        RAISE EXCEPTION 'Invalid classification status: %', p_status;
    END IF;
    IF NULLIF(btrim(p_cluster_key), '') IS NULL THEN
        RAISE EXCEPTION 'cluster_key is required';
    END IF;

    FOR v_title IN
        SELECT normalized_title
        FROM jobpush.job_title_review_queue
        WHERE jobpush.title_review_cluster_key(normalized_title) = p_cluster_key
        ORDER BY active_posting_count DESC, company_count DESC, normalized_title
        LIMIT GREATEST(1, COALESCE(p_limit, 5000))
    LOOP
        PERFORM jobpush.apply_manual_job_title_label(
            v_title,
            p_status,
            COALESCE(p_canonical_role, ''),
            COALESCE(NULLIF(btrim(p_reason), ''), 'dashboard title cluster review') || ' | cluster=' || p_cluster_key,
            p_labeled_by
        );
        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$;

COMMIT;

SELECT *
FROM jobpush.job_title_cluster_review_queue
ORDER BY active_postings DESC
LIMIT 20;
