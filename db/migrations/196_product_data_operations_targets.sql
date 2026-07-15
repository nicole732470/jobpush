BEGIN;

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    ('profile-title-rules-v2', '2026-07-15-user-confirmed', 'target',
     'candidate_profile_track: product', 'product operations',
     '(^|[^a-z])product operations?([^a-z]|$)',
     'nicole 2026-07-15', 'profile_target_product_operations', 1, TRUE),
    ('profile-title-rules-v2', '2026-07-15-user-confirmed', 'target',
     'candidate_profile_track: analyst/bi', 'data operations',
     '(^|[^a-z])data operations?([^a-z]|$)',
     'nicole 2026-07-15', 'profile_target_data_operations', 1, TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

-- These explicit multi-word targets override generic seniority exclusions.
-- A bare "analyst" remains review: it is not enough context to classify a job.
CREATE OR REPLACE FUNCTION jobpush.profile_title_rule_decision(p_title TEXT)
RETURNS TABLE(classification_status TEXT, canonical_role TEXT, decision_reason TEXT)
LANGUAGE sql
STABLE
AS $$
    WITH title AS (
        SELECT lower(coalesce(p_title, '')) AS value
    ), language_signal AS (
        SELECT 1 AS hit
        FROM title
        WHERE value ~ '(一|丁|七|万|三|上|下|不|中|人|会|体|作|保|入|全|公|出|分|利|前|務|動|化|北|区|医|南|同|名|員|品|営|国|在|地|場|士|外|大|学|定|実|家|小|市|年|店|後|心|情|手|担|支|教|新|方|日|明|時|月|本|業|様|機|正|法|活|海|理|生|用|発|的|社|管|系|経|者|職|自|行|製|見|計|語|販|資|車|近|部|都|開|電|面|食品|高级|经理|工程|销售|运营|数据|软件|产品|研发|中国|日本|日本語|中文|香港|台湾|东京|大阪|北京|上海|深圳|广州|杭州|南京|成都|武汉|苏州|서울|한국|[ぁ-ゟァ-ヿ가-힣])'
        LIMIT 1
    ), explicit_operations_target AS (
        SELECT term.canonical_role, term.decision_reason
        FROM title
        JOIN jobpush.profile_title_rule_terms term
          ON term.active
         AND term.rule_version = 'profile-title-rules-v2'
         AND term.rule_type = 'target'
         AND term.decision_reason IN ('profile_target_product_operations', 'profile_target_data_operations')
         AND title.value ~ term.regex_pattern
        ORDER BY term.priority, length(term.term) DESC, term.term
        LIMIT 1
    ), first_non_target AS (
        SELECT term.canonical_role, term.decision_reason
        FROM title
        JOIN jobpush.profile_title_rule_terms term
          ON term.active
         AND term.rule_version = 'profile-title-rules-v2'
         AND term.rule_type = 'non_target'
         AND title.value ~ term.regex_pattern
        ORDER BY term.priority, length(term.term) DESC, term.term
        LIMIT 1
    ), first_target AS (
        SELECT term.canonical_role, term.decision_reason
        FROM title
        JOIN jobpush.profile_title_rule_terms term
          ON term.active
         AND term.rule_version = 'profile-title-rules-v2'
         AND term.rule_type = 'target'
         AND title.value ~ term.regex_pattern
        ORDER BY term.priority, length(term.term) DESC, term.term
        LIMIT 1
    )
    SELECT
        CASE
            WHEN EXISTS (SELECT 1 FROM language_signal) THEN 'non_target'
            WHEN EXISTS (SELECT 1 FROM explicit_operations_target) THEN 'target'
            WHEN EXISTS (SELECT 1 FROM first_non_target) THEN 'non_target'
            WHEN EXISTS (SELECT 1 FROM first_target) THEN 'target'
            ELSE 'review'
        END,
        CASE
            WHEN EXISTS (SELECT 1 FROM language_signal) THEN NULL
            WHEN EXISTS (SELECT 1 FROM explicit_operations_target) THEN (SELECT canonical_role FROM explicit_operations_target)
            WHEN EXISTS (SELECT 1 FROM first_target) AND NOT EXISTS (SELECT 1 FROM first_non_target) THEN (SELECT canonical_role FROM first_target)
            ELSE NULL
        END,
        CASE
            WHEN EXISTS (SELECT 1 FROM language_signal) THEN 'profile_non_us_language_signal'
            WHEN EXISTS (SELECT 1 FROM explicit_operations_target) THEN (SELECT decision_reason FROM explicit_operations_target)
            WHEN EXISTS (SELECT 1 FROM first_non_target) THEN (SELECT decision_reason FROM first_non_target)
            WHEN EXISTS (SELECT 1 FROM first_target) THEN (SELECT decision_reason FROM first_target)
            ELSE 'profile_no_rule_match'
        END;
$$;

SELECT * FROM jobpush.reapply_latest_profile_title_rules();

COMMIT;

SELECT classification_status, canonical_role, decision_reason, count(*) AS titles
FROM jobpush.job_title_labels
WHERE normalized_title ~* '(^|[^a-z])(product|data) operations?([^a-z]|$)'
GROUP BY 1, 2, 3
ORDER BY titles DESC;
