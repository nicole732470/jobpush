BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.lca_wage_repair_stage (
    case_number TEXT PRIMARY KEY,
    wage_rate_of_pay_from TEXT,
    wage_rate_of_pay_to TEXT,
    wage_unit_of_pay TEXT,
    prevailing_wage TEXT,
    pw_unit_of_pay TEXT,
    pw_tracking_number TEXT,
    pw_wage_level TEXT,
    pw_oes_year TEXT,
    pw_other_source TEXT,
    pw_other_year TEXT,
    pw_survey_publisher TEXT,
    pw_survey_name TEXT
);

CREATE TABLE IF NOT EXISTS jobpush.lca_wage_repair_backup (
    repair_batch TEXT NOT NULL,
    lca_case_id BIGINT NOT NULL,
    case_number TEXT NOT NULL,
    old_wage_rate_of_pay_from NUMERIC,
    old_wage_rate_of_pay_to NUMERIC,
    old_wage_unit_of_pay TEXT,
    old_prevailing_wage NUMERIC,
    old_pw_unit_of_pay TEXT,
    old_pw_tracking_number TEXT,
    old_pw_wage_level TEXT,
    old_pw_oes_year TEXT,
    old_pw_other_source TEXT,
    old_pw_other_year TEXT,
    old_pw_survey_publisher TEXT,
    old_pw_survey_name TEXT,
    new_wage_rate_of_pay_from NUMERIC,
    new_wage_rate_of_pay_to NUMERIC,
    new_wage_unit_of_pay TEXT,
    new_prevailing_wage NUMERIC,
    new_pw_unit_of_pay TEXT,
    new_pw_tracking_number TEXT,
    new_pw_wage_level TEXT,
    new_pw_oes_year TEXT,
    new_pw_other_source TEXT,
    new_pw_other_year TEXT,
    new_pw_survey_publisher TEXT,
    new_pw_survey_name TEXT,
    repaired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (repair_batch, lca_case_id)
);

CREATE INDEX IF NOT EXISTS idx_lca_wage_repair_backup_case
    ON jobpush.lca_wage_repair_backup(case_number);

TRUNCATE jobpush.lca_wage_repair_stage;

COMMIT;
