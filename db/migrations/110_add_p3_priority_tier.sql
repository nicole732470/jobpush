BEGIN;

ALTER TABLE jobpush.company_targets_consolidated
    DROP CONSTRAINT IF EXISTS company_targets_consolidated_crawl_priority_tier_check,
    DROP CONSTRAINT IF EXISTS company_targets_consolidated_computed_tier_check;

ALTER TABLE jobpush.company_targets_consolidated
    ADD CONSTRAINT company_targets_consolidated_crawl_priority_tier_check
        CHECK (crawl_priority_tier IS NULL OR crawl_priority_tier IN ('P0', 'P1', 'P2', 'P3')),
    ADD CONSTRAINT company_targets_consolidated_computed_tier_check
        CHECK (computed_crawl_priority_tier IS NULL OR computed_crawl_priority_tier IN ('P1', 'P2', 'P3'));

ALTER TABLE jobpush.crawl_targets
    DROP CONSTRAINT IF EXISTS crawl_targets_priority_tier_check,
    DROP CONSTRAINT IF EXISTS crawl_targets_computed_priority_tier_check;

ALTER TABLE jobpush.crawl_targets
    ADD CONSTRAINT crawl_targets_priority_tier_check
        CHECK (priority_tier IN ('P0', 'P1', 'P2', 'P3')),
    ADD CONSTRAINT crawl_targets_computed_priority_tier_check
        CHECK (computed_priority_tier IS NULL OR computed_priority_tier IN ('P1', 'P2', 'P3'));

ALTER TABLE jobpush.crawl_priority_overrides
    DROP CONSTRAINT IF EXISTS crawl_priority_overrides_tier_check;

ALTER TABLE jobpush.crawl_priority_overrides
    ADD CONSTRAINT crawl_priority_overrides_tier_check
        CHECK (override_tier IN ('P0', 'P1', 'P2', 'P3'));

CREATE OR REPLACE FUNCTION jobpush.set_manual_crawl_priority(
    p_consolidation_key TEXT,
    p_tier TEXT,
    p_reason TEXT,
    p_changed_by TEXT DEFAULT 'nicole'
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_computed_tier TEXT;
BEGIN
    IF p_tier NOT IN ('P0', 'P1', 'P2', 'P3', 'AUTO') THEN
        RAISE EXCEPTION 'Tier must be P0, P1, P2, P3, or AUTO';
    END IF;

    SELECT computed_crawl_priority_tier
    INTO v_computed_tier
    FROM jobpush.company_targets_consolidated
    WHERE consolidation_key = p_consolidation_key;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown company consolidation_key: %', p_consolidation_key;
    END IF;

    IF p_tier = 'AUTO' THEN
        UPDATE jobpush.crawl_priority_overrides
        SET active = FALSE,
            reason = COALESCE(NULLIF(p_reason, ''), reason),
            created_by = p_changed_by,
            updated_at = now()
        WHERE consolidation_key = p_consolidation_key;

        UPDATE jobpush.company_targets_consolidated
        SET crawl_priority_tier = computed_crawl_priority_tier,
            updated_at = now()
        WHERE consolidation_key = p_consolidation_key;

        IF v_computed_tier IN ('P0', 'P1', 'P2', 'P3') THEN
            INSERT INTO jobpush.crawl_targets (
                consolidation_key, canonical_name, priority_tier,
                computed_priority_tier, priority_source, priority_override_reason,
                priority_score, enabled, next_discovery_at, created_at, updated_at
            )
            SELECT
                consolidation_key, canonical_name, v_computed_tier,
                computed_crawl_priority_tier, 'computed', NULL,
                priority_score, TRUE, now(), now(), now()
            FROM jobpush.company_targets_consolidated
            WHERE consolidation_key = p_consolidation_key
            ON CONFLICT (consolidation_key) DO UPDATE SET
                canonical_name = EXCLUDED.canonical_name,
                priority_tier = EXCLUDED.priority_tier,
                computed_priority_tier = EXCLUDED.computed_priority_tier,
                priority_source = 'computed',
                priority_override_reason = NULL,
                priority_score = EXCLUDED.priority_score,
                enabled = TRUE,
                updated_at = now();
        ELSE
            UPDATE jobpush.crawl_targets
            SET enabled = FALSE,
                computed_priority_tier = NULL,
                priority_source = 'computed',
                priority_override_reason = NULL,
                updated_at = now()
            WHERE consolidation_key = p_consolidation_key;
        END IF;

        RETURN;
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
    SET crawl_priority_tier = p_tier,
        updated_at = now()
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

COMMENT ON FUNCTION jobpush.set_manual_crawl_priority(TEXT, TEXT, TEXT, TEXT)
    IS 'Safely applies a persistent P0/P1/P2/P3 override, or clears it with AUTO.';

CREATE OR REPLACE VIEW jobpush.dashboard_crawl_funnel AS
SELECT
    (SELECT count(*) FROM jobpush.company_targets_consolidated) AS all_companies,
    (SELECT count(*) FROM jobpush.company_targets_consolidated WHERE target_role_score = 1) AS target_soc_companies,
    (SELECT count(*) FROM jobpush.company_targets_consolidated WHERE crawl_priority_tier = 'P0') AS p0_companies,
    (SELECT count(*) FROM jobpush.company_targets_consolidated WHERE crawl_priority_tier = 'P1') AS p1_companies,
    (SELECT count(*) FROM jobpush.company_targets_consolidated WHERE crawl_priority_tier = 'P2') AS p2_companies,
    (SELECT count(*) FROM jobpush.crawl_targets WHERE enabled) AS enabled_targets,
    (SELECT count(DISTINCT consolidation_key) FROM jobpush.career_sites WHERE verification_status = 'unverified') AS companies_with_candidates,
    (SELECT count(DISTINCT consolidation_key) FROM jobpush.career_sites WHERE verification_status = 'verified') AS companies_with_verified_site,
    (SELECT count(*) FROM jobpush.career_sites WHERE verification_status = 'verified' AND target_country_code = 'US' AND scope_method <> 'unknown') AS us_ready_sites,
    (SELECT count(*) FROM jobpush.career_sites WHERE verification_status = 'verified' AND source_type IN ('apple_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday')) AS adapter_supported_sites,
    (SELECT count(*) FROM jobpush.crawl_schedule_queue) AS schedulable_sites,
    (SELECT count(*) FROM jobpush.crawl_schedule_queue WHERE is_due) AS due_sites,
    (SELECT count(*) FROM jobpush.crawl_schedule_queue WHERE last_crawled_at IS NULL) AS never_crawled_schedulable_sites,
    (SELECT count(*) FROM jobpush.company_targets_consolidated WHERE crawl_priority_tier = 'P3') AS p3_companies;

COMMIT;
