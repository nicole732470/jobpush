BEGIN;

DO $$
DECLARE
    stage_rows INTEGER;
    affected_rows INTEGER;
    matched_rows INTEGER;
    invalid_units INTEGER;
BEGIN
    SELECT COUNT(*) INTO stage_rows FROM jobpush.lca_wage_repair_stage;
    IF stage_rows <> 107414 THEN
        RAISE EXCEPTION 'Expected 107414 official Q1 rows, found %', stage_rows;
    END IF;

    SELECT COUNT(*) INTO affected_rows
    FROM public.lca_cases
    WHERE decision_date BETWEEN DATE '2024-10-01' AND DATE '2024-12-31'
      AND wage_unit_of_pay ~ '^[0-9]+([.][0-9]+)?$';

    SELECT COUNT(*) INTO matched_rows
    FROM public.lca_cases lcase
    JOIN jobpush.lca_wage_repair_stage stage
      ON stage.case_number = lcase.case_number
    WHERE lcase.decision_date BETWEEN DATE '2024-10-01' AND DATE '2024-12-31'
      AND lcase.wage_unit_of_pay ~ '^[0-9]+([.][0-9]+)?$';

    IF affected_rows <> 104046 OR matched_rows <> affected_rows THEN
        RAISE EXCEPTION 'Expected 104046 affected/matched rows, found affected %, matched %',
            affected_rows, matched_rows;
    END IF;

    SELECT COUNT(*) INTO invalid_units
    FROM jobpush.lca_wage_repair_stage
    WHERE NULLIF(BTRIM(wage_unit_of_pay), '') IS NOT NULL
      AND wage_unit_of_pay NOT IN ('Year', 'Month', 'Bi-Weekly', 'Week', 'Hour');
    IF invalid_units <> 0 THEN
        RAISE EXCEPTION 'Official Q1 stage contains % unexpected wage units', invalid_units;
    END IF;
END $$;

INSERT INTO jobpush.lca_wage_repair_backup (
    repair_batch, lca_case_id, case_number,
    old_wage_rate_of_pay_from, old_wage_rate_of_pay_to, old_wage_unit_of_pay,
    old_prevailing_wage, old_pw_unit_of_pay, old_pw_tracking_number,
    old_pw_wage_level, old_pw_oes_year, old_pw_other_source, old_pw_other_year,
    old_pw_survey_publisher, old_pw_survey_name,
    new_wage_rate_of_pay_from, new_wage_rate_of_pay_to, new_wage_unit_of_pay,
    new_prevailing_wage, new_pw_unit_of_pay, new_pw_tracking_number,
    new_pw_wage_level, new_pw_oes_year, new_pw_other_source, new_pw_other_year,
    new_pw_survey_publisher, new_pw_survey_name
)
SELECT
    'fy2025-q1-official', lcase.lca_case_id, lcase.case_number,
    lcase.wage_rate_of_pay_from, lcase.wage_rate_of_pay_to, lcase.wage_unit_of_pay,
    lcase.prevailing_wage, lcase.pw_unit_of_pay, lcase.pw_tracking_number,
    lcase.pw_wage_level, lcase.pw_oes_year, lcase.pw_other_source, lcase.pw_other_year,
    lcase.pw_survey_publisher, lcase.pw_survey_name,
    NULLIF(stage.wage_rate_of_pay_from, '')::NUMERIC,
    NULLIF(stage.wage_rate_of_pay_to, '')::NUMERIC,
    NULLIF(stage.wage_unit_of_pay, ''),
    NULLIF(stage.prevailing_wage, '')::NUMERIC,
    NULLIF(stage.pw_unit_of_pay, ''), NULLIF(stage.pw_tracking_number, ''),
    NULLIF(stage.pw_wage_level, ''), NULLIF(stage.pw_oes_year, ''),
    NULLIF(stage.pw_other_source, ''), NULLIF(stage.pw_other_year, ''),
    NULLIF(stage.pw_survey_publisher, ''), NULLIF(stage.pw_survey_name, '')
FROM public.lca_cases lcase
JOIN jobpush.lca_wage_repair_stage stage
  ON stage.case_number = lcase.case_number
WHERE lcase.decision_date BETWEEN DATE '2024-10-01' AND DATE '2024-12-31'
  AND lcase.wage_unit_of_pay ~ '^[0-9]+([.][0-9]+)?$'
ON CONFLICT (repair_batch, lca_case_id) DO NOTHING;

UPDATE public.lca_cases lcase
SET
    wage_rate_of_pay_from = backup.new_wage_rate_of_pay_from,
    wage_rate_of_pay_to = backup.new_wage_rate_of_pay_to,
    wage_unit_of_pay = backup.new_wage_unit_of_pay,
    prevailing_wage = backup.new_prevailing_wage,
    pw_unit_of_pay = backup.new_pw_unit_of_pay,
    pw_tracking_number = backup.new_pw_tracking_number,
    pw_wage_level = backup.new_pw_wage_level,
    pw_oes_year = backup.new_pw_oes_year,
    pw_other_source = backup.new_pw_other_source,
    pw_other_year = backup.new_pw_other_year,
    pw_survey_publisher = backup.new_pw_survey_publisher,
    pw_survey_name = backup.new_pw_survey_name
FROM jobpush.lca_wage_repair_backup backup
WHERE backup.repair_batch = 'fy2025-q1-official'
  AND backup.lca_case_id = lcase.lca_case_id;

DO $$
DECLARE
    repaired_rows INTEGER;
    remaining_numeric_units INTEGER;
BEGIN
    SELECT COUNT(*) INTO repaired_rows
    FROM jobpush.lca_wage_repair_backup
    WHERE repair_batch = 'fy2025-q1-official';
    IF repaired_rows <> 104046 THEN
        RAISE EXCEPTION 'Expected 104046 backup rows, found %', repaired_rows;
    END IF;

    SELECT COUNT(*) INTO remaining_numeric_units
    FROM public.lca_cases
    WHERE decision_date BETWEEN DATE '2024-10-01' AND DATE '2024-12-31'
      AND wage_unit_of_pay ~ '^[0-9]+([.][0-9]+)?$';
    IF remaining_numeric_units <> 0 THEN
        RAISE EXCEPTION '% numeric wage units remain after repair', remaining_numeric_units;
    END IF;
END $$;

COMMIT;
