BEGIN;

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
    IF p_tier NOT IN ('P0', 'P1', 'P2', 'AUTO') THEN
        RAISE EXCEPTION 'Tier must be P0, P1, P2, or AUTO';
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

        IF v_computed_tier IN ('P0', 'P1', 'P2') THEN
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
    IS 'Safely applies a persistent P0/P1/P2 override, or clears it with AUTO.';

SELECT jobpush.set_manual_crawl_priority(
    '26-0072915',
    'AUTO',
    'Remove Barry Callebaut USA LLC manual P2 after Chief Executives target SOC exclusion',
    'nicole'
);

COMMIT;

SELECT target.consolidation_key, target.canonical_name, target.priority_tier,
       target.enabled, target.priority_source, target.priority_override_reason,
       consolidated.crawl_priority_tier, consolidated.computed_crawl_priority_tier,
       consolidated.target_role_score, consolidated.priority_score,
       override.override_tier, override.active AS override_active
FROM jobpush.company_targets_consolidated consolidated
LEFT JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN jobpush.crawl_priority_overrides override USING (consolidation_key)
WHERE consolidated.consolidation_key = '26-0072915';
