BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.profile_title_rule_terms (
    term_id BIGSERIAL PRIMARY KEY,
    rule_version TEXT NOT NULL,
    profile_version TEXT NOT NULL,
    rule_type TEXT NOT NULL,
    canonical_role TEXT,
    term TEXT NOT NULL,
    regex_pattern TEXT NOT NULL,
    source TEXT NOT NULL,
    decision_reason TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 100,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT profile_title_rule_terms_type_check
        CHECK (rule_type IN ('target', 'non_target'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_title_rule_terms_active
    ON jobpush.profile_title_rule_terms(rule_version, rule_type, lower(term), regex_pattern);

CREATE INDEX IF NOT EXISTS idx_profile_title_rule_terms_lookup
    ON jobpush.profile_title_rule_terms(rule_type, active, priority);

UPDATE jobpush.profile_title_rule_terms
SET active = FALSE
WHERE rule_version = 'profile-title-rules-v2';

INSERT INTO jobpush.profile_title_rule_terms (
    rule_version, profile_version, rule_type, canonical_role,
    term, regex_pattern, source, decision_reason, priority, active
) VALUES
    -- hard avoid: non-US language / location signals remain in function because they are character classes.
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'lead','(^|[^a-z])(lead)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'staff','(^|[^a-z])(staff)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'principal','(^|[^a-z])(principal)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'director','(^|[^a-z])(director)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'executive director','(^|[^a-z])(executive director)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'vice president','(^|[^a-z])(vice president|vp)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'head','(^|[^a-z])(head)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'chief','(^|[^a-z])(chief|ceo|cto|cfo|coo|cio)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'distinguished','(^|[^a-z])(distinguished|fellow)([^a-z]|$)','candidate_profile.seniority_policy.hard_exclude_levels','profile_hard_seniority_exclusion',10,TRUE),

    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'machine learning','(^|[^a-z])(machine learning|ml engineer|ml research|machine learning researcher|applied scientist|research scientist|research engineer|scientist)([^a-z]|$)','candidate_profile.avoid_tracks + technical_scope.hard_exclude_domains','profile_avoid_ml_research_roles',20,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'mechanical/electrical/hardware','(^|[^a-z])(mechanical|electrical|cad|eda|embedded|firmware|rf|antenna|phy|analog|mixed[- ]signal|circuit|asic|rtl|physical design|silicon|semiconductor|hardware|cpu|gpu|soc|chip)([^a-z]|$)','candidate_profile.avoid_tracks + technical_scope.hard_exclude_domains','profile_hard_technical_exclusion',20,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'hr/recruiting','(^|[^a-z])(human resources|hr business|hr generalist|hr specialist|recruiter|recruiting|talent acquisition|people partner|people operations|people ops)([^a-z]|$)','nicole_review_2026-06-24','profile_avoid_hr_people_roles',25,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'accounting/tax/audit','(^|[^a-z])(accountant|accounting|auditor|audit|tax associate|tax senior|tax consultant|revenue accountant|bookkeeper|payroll)([^a-z]|$)','nicole_review_2026-06-24','profile_avoid_accounting_tax_roles',25,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'warehouse/retail/in-store','(^|[^a-z])(warehouse|retail|in[- ]store|store manager|store associate|assistant store manager|cashier|merchandis|xfinity|field sales|retail sales|sales consultant|sales professional|sales representative|customer service representative|call center|store sales|shopper)([^a-z]|$)','nicole_review_2026-06-24','profile_avoid_retail_warehouse_instore_sales',25,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','non_target',NULL,'manufacturing/factory','(^|[^a-z])(manufacturing|manufacturer|production|factory|plant operator|assembler|machine operator|maintenance technician|quality technician|process technician|equipment technician)([^a-z]|$)','nicole_review_2026-06-24','profile_avoid_manufacturing_roles',25,TRUE),

    ('profile-title-rules-v2','2026-06-23-draft-1','target','candidate_profile_track: product','product manager','(^|[^a-z])(product manager|technical product manager|associate product manager|product owner|product specialist|product analyst|product marketing manager|product engineer)([^a-z]|$)','candidate_profile.tracks.pm_eng','profile_target_product_track',50,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','target','candidate_profile_track: solutions/systems','solutions roles','(^|[^a-z])(system engineer|systems engineer|solution architect|solutions architect|solution engineer|solutions engineer|sales engineer|developer relations|developer advocate)([^a-z]|$)','candidate_profile.tracks.pm_eng','profile_target_solutions_track',50,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','target','candidate_profile_track: applied_ai','applied ai','(^|[^a-z])(ai engineer|ai developer|forward deployed engineer|ai builder|agentic ai engineer|llm application engineer|applied ai|gen ai|generative ai)([^a-z]|$)','candidate_profile.tracks.ai_eng','profile_target_applied_ai_track',55,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','target','candidate_profile_track: customer_success','customer success','(^|[^a-z])(customer success|technical customer success|customer success manager|technical account manager|technical account|csm)([^a-z]|$)','candidate_profile.tracks.customer_success','profile_target_customer_success_track',60,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','target','candidate_profile_track: software/data','software engineering','(^|[^a-z])(software engineer|software developer|software engineering|full[- ]stack|backend|front[- ]end|frontend|devops|cloud engineer|data engineer|qa engineer|test engineer|cybersecurity|security engineer)([^a-z]|$)','candidate_profile.tracks.sde_eng','profile_target_software_data_track',65,TRUE),
    ('profile-title-rules-v2','2026-06-23-draft-1','target','candidate_profile_track: analyst/bi','analyst/bi','(^|[^a-z])(data analyst|business analyst|business intelligence|bi analyst|bi engineer|systems analyst|consultant|marketing specialist|marketing analyst|marketing insights)([^a-z]|$)','candidate_profile.tracks.business_analyst + nicole_review_2026-06-24','profile_target_analyst_marketing_track',70,TRUE)
ON CONFLICT (rule_version, rule_type, lower(term), regex_pattern) DO UPDATE SET
    profile_version = EXCLUDED.profile_version,
    canonical_role = EXCLUDED.canonical_role,
    source = EXCLUDED.source,
    decision_reason = EXCLUDED.decision_reason,
    priority = EXCLUDED.priority,
    active = TRUE;

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
            WHEN EXISTS (SELECT 1 FROM first_non_target) THEN 'non_target'
            WHEN EXISTS (SELECT 1 FROM first_target) THEN 'target'
            ELSE 'review'
        END AS classification_status,
        CASE
            WHEN EXISTS (SELECT 1 FROM first_target) AND NOT EXISTS (SELECT 1 FROM language_signal) AND NOT EXISTS (SELECT 1 FROM first_non_target)
                THEN (SELECT canonical_role FROM first_target)
            ELSE NULL
        END AS canonical_role,
        CASE
            WHEN EXISTS (SELECT 1 FROM language_signal) THEN 'profile_non_us_language_signal'
            WHEN EXISTS (SELECT 1 FROM first_non_target) THEN (SELECT decision_reason FROM first_non_target)
            WHEN EXISTS (SELECT 1 FROM first_target) THEN (SELECT decision_reason FROM first_target)
            ELSE 'profile_no_rule_match'
        END AS decision_reason;
$$;

CREATE OR REPLACE FUNCTION jobpush.apply_profile_title_boundary()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_decision RECORD;
BEGIN
    IF COALESCE(NEW.rule_version, '') LIKE 'manual%%' THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_decision
    FROM jobpush.profile_title_rule_decision(NEW.normalized_title)
    LIMIT 1;

    IF v_decision.classification_status IN ('target', 'non_target') THEN
        NEW.classification_status := v_decision.classification_status;
        NEW.canonical_role := v_decision.canonical_role;
        NEW.rule_version := 'profile-title-rules-v2';
        NEW.decision_reason := v_decision.decision_reason || ': candidate_profile 2026-06-24';
        NEW.labeled_by := 'system:profile-title-rules-v2';
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
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status IN ('target', 'non_target')
      AND (label.classification_status IS DISTINCT FROM decision.classification_status
           OR label.rule_version IS DISTINCT FROM 'profile-title-rules-v2'
           OR label.canonical_role IS DISTINCT FROM decision.canonical_role)
)
INSERT INTO jobpush.job_title_label_history (
    normalized_title, previous_status, new_status, canonical_role,
    decision_reason, labeled_by
)
SELECT normalized_title, previous_status, new_status, canonical_role,
       decision_reason || ': candidate_profile 2026-06-24',
       'system:profile-title-rules-v2'
FROM proposed;

WITH proposed AS (
    SELECT label.normalized_title,
           decision.classification_status AS new_status,
           decision.canonical_role,
           decision.decision_reason
    FROM jobpush.job_title_labels label
    CROSS JOIN LATERAL jobpush.profile_title_rule_decision(label.normalized_title) decision
    WHERE COALESCE(label.rule_version, '') NOT LIKE 'manual%%'
      AND decision.classification_status IN ('target', 'non_target')
)
UPDATE jobpush.job_title_labels label
SET classification_status = proposed.new_status,
    canonical_role = proposed.canonical_role,
    rule_version = 'profile-title-rules-v2',
    decision_reason = proposed.decision_reason || ': candidate_profile 2026-06-24',
    labeled_by = 'system:profile-title-rules-v2',
    labeled_at = now(),
    updated_at = now()
FROM proposed
WHERE label.normalized_title = proposed.normalized_title
  AND COALESCE(label.rule_version, '') NOT LIKE 'manual%%';

UPDATE jobpush.job_postings
SET market_scope = 'non-US',
    updated_at = now()
WHERE market_scope = 'US'
  AND coalesce(title, '') ~
      '(一|丁|七|万|三|上|下|不|中|人|会|体|作|保|入|全|公|出|分|利|前|務|動|化|北|区|医|南|同|名|員|品|営|国|在|地|場|士|外|大|学|定|実|家|小|市|年|店|後|心|情|手|担|支|教|新|方|日|明|時|月|本|業|様|機|正|法|活|海|理|生|用|発|的|社|管|系|経|者|職|自|行|製|見|計|語|販|資|車|近|部|都|開|電|面|食品|高级|经理|工程|销售|运营|数据|软件|产品|研发|中国|日本|日本語|中文|香港|台湾|东京|大阪|北京|上海|深圳|广州|杭州|南京|成都|武汉|苏州|서울|한국|[ぁ-ゟァ-ヿ가-힣])';

COMMIT;
