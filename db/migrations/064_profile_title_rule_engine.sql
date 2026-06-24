BEGIN;

CREATE OR REPLACE FUNCTION jobpush.profile_title_rule_decision(p_title TEXT)
RETURNS TABLE(classification_status TEXT, canonical_role TEXT, decision_reason TEXT)
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        CASE
            WHEN lower(coalesce(p_title, '')) ~
                '(一|丁|七|万|三|上|下|不|中|人|会|体|作|保|入|全|公|出|分|利|前|務|動|化|北|区|医|南|同|名|員|品|営|国|在|地|場|士|外|大|学|定|実|家|小|市|年|店|後|心|情|手|担|支|教|新|方|日|明|時|月|本|業|様|機|正|法|活|海|理|生|用|発|的|社|管|系|経|者|職|自|行|製|見|計|語|販|資|車|近|部|都|開|電|面|食品|高级|经理|工程|销售|运营|数据|软件|产品|研发|中国|日本|日本語|中文|香港|台湾|东京|大阪|北京|上海|深圳|广州|杭州|南京|成都|武汉|苏州|서울|한국|[ぁ-ゟァ-ヿ가-힣])'
                THEN 'non_target'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(lead|staff|principal|director|executive director|vice president|vp|head|chief|distinguished|fellow)([^a-z]|$)'
                THEN 'non_target'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(machine learning|ml engineer|ml research|mechanical|electrical|cad|eda|embedded|firmware|rf|antenna|phy|analog|mixed[- ]signal|circuit|asic|rtl|physical design|silicon|semiconductor|hardware architecture|hardware engineer|hardware systems?)([^a-z]|$)'
                THEN 'non_target'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(human resources|hr business|hr generalist|recruiter|recruiting|talent acquisition|people partner|people operations)([^a-z]|$)'
                THEN 'non_target'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(accountant|accounting|auditor|audit|tax associate|tax senior|tax consultant|revenue accountant)([^a-z]|$)'
                THEN 'non_target'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(warehouse|retail|in[- ]store|store manager|store associate|assistant store manager|cashier|merchandis|xfinity|field sales|retail sales|sales consultant|sales professional|sales representative|customer service representative|call center)([^a-z]|$)'
                THEN 'non_target'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(manufacturing operator|manufacturing technician|manufacturing specialist|manufacturing assembler|manufacturing process|manufacturing equipment|manufacturing quality|manufacturing engineer|manufacturing design|production engineer|factory|plant operator)([^a-z]|$)'
                THEN 'non_target'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(product manager|technical product manager|product owner|product specialist|product marketing manager)([^a-z]|$)'
                THEN 'target'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(software engineer|software developer|software engineering|full[- ]stack|backend|front[- ]end|frontend|devops|cloud engineer|data engineer|data analyst|business analyst|business intelligence|systems analyst|solution architect|solutions architect|solution engineer|solutions engineer)([^a-z]|$)'
                THEN 'target'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(customer success|technical account|applied ai|gen ai|generative ai|llm application|ai engineer|marketing specialist|marketing analyst|marketing insights)([^a-z]|$)'
                THEN 'target'
            ELSE 'review'
        END,
        CASE
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(product manager|technical product manager|product owner|product specialist|product marketing manager)([^a-z]|$)'
                THEN 'candidate_profile_track: product/marketing'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(software engineer|software developer|software engineering|full[- ]stack|backend|front[- ]end|frontend|devops|cloud engineer|data engineer|data analyst|business analyst|business intelligence|systems analyst|solution architect|solutions architect|solution engineer|solutions engineer)([^a-z]|$)'
                THEN 'candidate_profile_track: software/data/solutions'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(customer success|technical account|applied ai|gen ai|generative ai|llm application|ai engineer|marketing specialist|marketing analyst|marketing insights)([^a-z]|$)'
                THEN 'candidate_profile_track: applied_ai/customer_success/marketing'
            ELSE NULL
        END,
        CASE
            WHEN lower(coalesce(p_title, '')) ~
                '(一|丁|七|万|三|上|下|不|中|人|会|体|作|保|入|全|公|出|分|利|前|務|動|化|北|区|医|南|同|名|員|品|営|国|在|地|場|士|外|大|学|定|実|家|小|市|年|店|後|心|情|手|担|支|教|新|方|日|明|時|月|本|業|様|機|正|法|活|海|理|生|用|発|的|社|管|系|経|者|職|自|行|製|見|計|語|販|資|車|近|部|都|開|電|面|食品|高级|经理|工程|销售|运营|数据|软件|产品|研发|中国|日本|日本語|中文|香港|台湾|东京|大阪|北京|上海|深圳|广州|杭州|南京|成都|武汉|苏州|서울|한국|[ぁ-ゟァ-ヿ가-힣])'
                THEN 'profile_non_us_language_signal'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(human resources|hr business|hr generalist|recruiter|recruiting|talent acquisition|people partner|people operations)([^a-z]|$)'
                THEN 'profile_avoid_hr_people_roles'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(accountant|accounting|auditor|audit|tax associate|tax senior|tax consultant|revenue accountant)([^a-z]|$)'
                THEN 'profile_avoid_accounting_tax_roles'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(warehouse|retail|in[- ]store|store manager|store associate|assistant store manager|cashier|merchandis|xfinity|field sales|retail sales|sales consultant|sales professional|sales representative|customer service representative|call center)([^a-z]|$)'
                THEN 'profile_avoid_retail_warehouse_instore_sales'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(manufacturing operator|manufacturing technician|manufacturing specialist|manufacturing assembler|manufacturing process|manufacturing equipment|manufacturing quality|manufacturing engineer|manufacturing design|production engineer|factory|plant operator)([^a-z]|$)'
                THEN 'profile_avoid_manufacturing_roles'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(lead|staff|principal|director|executive director|vice president|vp|head|chief|distinguished|fellow)([^a-z]|$)'
                THEN 'profile_hard_seniority_exclusion'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(machine learning|ml engineer|ml research|mechanical|electrical|cad|eda|embedded|firmware|rf|antenna|phy|analog|mixed[- ]signal|circuit|asic|rtl|physical design|silicon|semiconductor|hardware architecture|hardware engineer|hardware systems?)([^a-z]|$)'
                THEN 'profile_hard_technical_exclusion'
            WHEN lower(coalesce(p_title, '')) ~
                '(^|[^a-z])(product manager|technical product manager|product owner|product specialist|product marketing manager|software engineer|software developer|software engineering|full[- ]stack|backend|front[- ]end|frontend|devops|cloud engineer|data engineer|data analyst|business analyst|business intelligence|systems analyst|solution architect|solutions architect|solution engineer|solutions engineer|customer success|technical account|applied ai|gen ai|generative ai|llm application|ai engineer|marketing specialist|marketing analyst|marketing insights)([^a-z]|$)'
                THEN 'profile_target_track_match'
            ELSE 'profile_no_rule_match'
        END
$$;

CREATE OR REPLACE FUNCTION jobpush.apply_profile_title_boundary()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_decision RECORD;
BEGIN
    IF COALESCE(NEW.rule_version, '') LIKE 'manual%'
       OR NEW.classification_status <> 'review'
    THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_decision
    FROM jobpush.profile_title_rule_decision(NEW.normalized_title)
    LIMIT 1;

    IF v_decision.classification_status IN ('target', 'non_target') THEN
        NEW.classification_status := v_decision.classification_status;
        NEW.canonical_role := v_decision.canonical_role;
        NEW.rule_version := 'profile-title-rules-v1';
        NEW.decision_reason := v_decision.decision_reason || ': candidate_profile 2026-06-24';
        NEW.labeled_by := 'system:profile-title-rules-v1';
        NEW.labeled_at := now();
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_profile_title_boundary
    ON jobpush.job_title_labels;
CREATE TRIGGER trg_apply_profile_title_boundary
BEFORE INSERT OR UPDATE OF normalized_title, classification_status, rule_version
ON jobpush.job_title_labels
FOR EACH ROW EXECUTE FUNCTION jobpush.apply_profile_title_boundary();

WITH proposed AS (
    SELECT label.normalized_title,
           label.classification_status AS previous_status,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE label.classification_status = 'review'
      AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status IN ('target', 'non_target')
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-06-24',
       'system:profile-title-rules-v1'
FROM proposed;

WITH proposed AS (
    SELECT label.normalized_title,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE label.classification_status = 'review'
      AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status IN ('target', 'non_target')
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'profile-title-rules-v1',
    decision_reason = proposed.decision_reason || ': candidate_profile 2026-06-24',
    labeled_by = 'system:profile-title-rules-v1',
    labeled_at = now(),
    updated_at = now()
FROM proposed
WHERE label.normalized_title = proposed.normalized_title;

UPDATE jobpush.job_postings
SET market_scope = 'non-US',
    updated_at = now()
WHERE market_scope = 'US'
  AND coalesce(title, '') ~
      '(一|丁|七|万|三|上|下|不|中|人|会|体|作|保|入|全|公|出|分|利|前|務|動|化|北|区|医|南|同|名|員|品|営|国|在|地|場|士|外|大|学|定|実|家|小|市|年|店|後|心|情|手|担|支|教|新|方|日|明|時|月|本|業|様|機|正|法|活|海|理|生|用|発|的|社|管|系|経|者|職|自|行|製|見|計|語|販|資|車|近|部|都|開|電|面|食品|高级|经理|工程|销售|运营|数据|软件|产品|研发|中国|日本|日本語|中文|香港|台湾|东京|大阪|北京|上海|深圳|广州|杭州|南京|成都|武汉|苏州|서울|한국|[ぁ-ゟァ-ヿ가-힣])';

COMMIT;
