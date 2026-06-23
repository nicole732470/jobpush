BEGIN;

CREATE OR REPLACE FUNCTION jobpush.set_manual_crawl_priority(
    p_consolidation_key TEXT,
    p_tier TEXT,
    p_reason TEXT,
    p_changed_by TEXT DEFAULT 'nicole'
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_tier NOT IN ('P0', 'P1', 'P2') THEN
        RAISE EXCEPTION 'Tier must be P0, P1, or P2';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM jobpush.company_targets_consolidated
        WHERE consolidation_key = p_consolidation_key
    ) THEN
        RAISE EXCEPTION 'Unknown company consolidation_key: %', p_consolidation_key;
    END IF;

    INSERT INTO jobpush.crawl_priority_overrides (
        consolidation_key, override_tier, reason, created_by, active
    ) VALUES (
        p_consolidation_key, p_tier, p_reason, p_changed_by, TRUE
    )
    ON CONFLICT (consolidation_key) DO UPDATE SET
        override_tier = EXCLUDED.override_tier,
        reason = EXCLUDED.reason,
        created_by = EXCLUDED.created_by,
        active = TRUE,
        updated_at = now();

    UPDATE jobpush.company_targets_consolidated
    SET crawl_priority_tier = p_tier
    WHERE consolidation_key = p_consolidation_key;

    INSERT INTO jobpush.crawl_targets (
        consolidation_key, canonical_name, priority_tier,
        computed_priority_tier, priority_source, priority_override_reason,
        priority_score, enabled, next_discovery_at, created_at, updated_at
    )
    SELECT
        consolidation_key, canonical_name, p_tier,
        computed_crawl_priority_tier, 'manual_override', p_reason,
        priority_score, TRUE, now(), now(), now()
    FROM jobpush.company_targets_consolidated
    WHERE consolidation_key = p_consolidation_key
    ON CONFLICT (consolidation_key) DO UPDATE SET
        priority_tier = EXCLUDED.priority_tier,
        priority_source = 'manual_override',
        priority_override_reason = EXCLUDED.priority_override_reason,
        enabled = TRUE,
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION jobpush.reject_all_career_site_candidates(
    p_consolidation_key TEXT,
    p_reviewed_by TEXT DEFAULT 'nicole',
    p_notes TEXT DEFAULT 'All current candidates are incorrect'
) RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_rejected INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM jobpush.crawl_targets
        WHERE consolidation_key = p_consolidation_key
    ) THEN
        RAISE EXCEPTION 'Unknown crawl target: %', p_consolidation_key;
    END IF;

    UPDATE jobpush.career_sites
    SET verification_status = 'rejected',
        crawl_enabled = FALSE,
        next_crawl_at = NULL,
        reviewed_at = now(),
        reviewed_by = NULLIF(btrim(p_reviewed_by), ''),
        review_notes = p_notes,
        updated_at = now()
    WHERE consolidation_key = p_consolidation_key
      AND verification_status = 'unverified';
    GET DIAGNOSTICS v_rejected = ROW_COUNT;

    UPDATE jobpush.crawl_targets
    SET discovery_status = CASE WHEN EXISTS (
            SELECT 1 FROM jobpush.career_sites
            WHERE consolidation_key = p_consolidation_key
              AND verification_status = 'verified'
        ) THEN 'found' ELSE 'not_found' END,
        next_discovery_at = CASE WHEN EXISTS (
            SELECT 1 FROM jobpush.career_sites
            WHERE consolidation_key = p_consolidation_key
              AND verification_status = 'verified'
        ) THEN NULL ELSE now() + interval '30 days' END,
        updated_at = now()
    WHERE consolidation_key = p_consolidation_key;

    RETURN v_rejected;
END;
$$;

CREATE OR REPLACE FUNCTION jobpush.verify_career_site_candidate(
    p_site_id BIGINT,
    p_reviewed_by TEXT DEFAULT 'nicole',
    p_notes TEXT DEFAULT 'Confirmed official career site',
    p_target_country_code TEXT DEFAULT NULL,
    p_scope_method TEXT DEFAULT 'unknown'
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_company_key TEXT;
BEGIN
    SELECT consolidation_key INTO v_company_key
    FROM jobpush.career_sites
    WHERE site_id = p_site_id;

    IF v_company_key IS NULL THEN
        RAISE EXCEPTION 'Unknown career site_id: %', p_site_id;
    END IF;

    PERFORM jobpush.review_career_site(
        p_site_id, 'verified', p_reviewed_by, p_notes
    );

    UPDATE jobpush.career_sites
    SET target_country_code = p_target_country_code,
        scope_method = p_scope_method,
        updated_at = now()
    WHERE site_id = p_site_id;

    UPDATE jobpush.career_sites
    SET verification_status = 'rejected',
        crawl_enabled = FALSE,
        next_crawl_at = NULL,
        reviewed_at = now(),
        reviewed_by = NULLIF(btrim(p_reviewed_by), ''),
        review_notes = 'Rejected because another candidate was verified: site_id ' || p_site_id,
        updated_at = now()
    WHERE consolidation_key = v_company_key
      AND site_id <> p_site_id
      AND verification_status = 'unverified';
END;
$$;

CREATE OR REPLACE FUNCTION jobpush.add_verified_career_site(
    p_consolidation_key TEXT,
    p_site_url TEXT,
    p_source_type TEXT DEFAULT 'unknown',
    p_source_key TEXT DEFAULT NULL,
    p_target_country_code TEXT DEFAULT NULL,
    p_scope_method TEXT DEFAULT 'unknown',
    p_reviewed_by TEXT DEFAULT 'nicole',
    p_notes TEXT DEFAULT 'Manually supplied official career site'
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_site_id BIGINT;
    v_domain TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM jobpush.crawl_targets
        WHERE consolidation_key = p_consolidation_key
    ) THEN
        RAISE EXCEPTION 'Unknown crawl target: %', p_consolidation_key;
    END IF;

    IF p_site_url !~* '^https?://' THEN
        RAISE EXCEPTION 'Career URL must start with http:// or https://';
    END IF;

    v_domain := lower(substring(p_site_url FROM '^https?://(?:www\.)?([^/:?#]+)'));

    INSERT INTO jobpush.career_sites (
        consolidation_key, site_url, normalized_domain, site_kind,
        source_type, source_key, discovery_source, verification_status,
        crawl_enabled, crawl_status, next_crawl_at, target_country_code,
        scope_method, reviewed_at, reviewed_by, review_notes, notes,
        created_at, updated_at
    ) VALUES (
        p_consolidation_key, p_site_url, v_domain,
        CASE WHEN p_source_type = 'unknown' THEN 'careers' ELSE 'ats_feed' END,
        p_source_type, p_source_key, 'manual', 'verified', TRUE, 'pending', now(),
        p_target_country_code, p_scope_method, now(),
        NULLIF(btrim(p_reviewed_by), ''), p_notes, p_notes, now(), now()
    )
    ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
        normalized_domain = EXCLUDED.normalized_domain,
        source_type = EXCLUDED.source_type,
        source_key = COALESCE(EXCLUDED.source_key, jobpush.career_sites.source_key),
        verification_status = 'verified',
        crawl_enabled = TRUE,
        crawl_status = 'pending',
        next_crawl_at = now(),
        target_country_code = EXCLUDED.target_country_code,
        scope_method = EXCLUDED.scope_method,
        reviewed_at = now(),
        reviewed_by = EXCLUDED.reviewed_by,
        review_notes = EXCLUDED.review_notes,
        updated_at = now()
    RETURNING site_id INTO v_site_id;

    UPDATE jobpush.career_sites
    SET verification_status = 'rejected',
        crawl_enabled = FALSE,
        next_crawl_at = NULL,
        reviewed_at = now(),
        reviewed_by = NULLIF(btrim(p_reviewed_by), ''),
        review_notes = 'Rejected because a manually supplied site was verified: site_id ' || v_site_id,
        updated_at = now()
    WHERE consolidation_key = p_consolidation_key
      AND site_id <> v_site_id
      AND verification_status = 'unverified';

    UPDATE jobpush.crawl_targets
    SET discovery_status = 'found', next_discovery_at = NULL, updated_at = now()
    WHERE consolidation_key = p_consolidation_key;

    RETURN v_site_id;
END;
$$;

COMMENT ON FUNCTION jobpush.set_manual_crawl_priority(TEXT, TEXT, TEXT, TEXT)
    IS 'Safely applies a persistent P0/P1/P2 override without a full scoring refresh.';
COMMENT ON FUNCTION jobpush.reject_all_career_site_candidates(TEXT, TEXT, TEXT)
    IS 'Rejects all currently unverified candidates for one company and returns the count.';
COMMENT ON FUNCTION jobpush.verify_career_site_candidate(BIGINT, TEXT, TEXT, TEXT, TEXT)
    IS 'Verifies one candidate and rejects the company other unverified candidates.';
COMMENT ON FUNCTION jobpush.add_verified_career_site(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)
    IS 'Adds a manually found official career URL and rejects stale unverified candidates.';

COMMIT;
