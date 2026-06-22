BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.product_role_title_rules (
    rule_key     TEXT PRIMARY KEY,
    category     TEXT NOT NULL,
    match_kind   TEXT NOT NULL CHECK (match_kind IN ('contains', 'exclude')),
    pattern      TEXT NOT NULL,
    sort_order   INTEGER NOT NULL DEFAULT 100,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    description  TEXT NOT NULL
);

TRUNCATE jobpush.product_role_title_rules;

INSERT INTO jobpush.product_role_title_rules (
    rule_key, category, match_kind, pattern, sort_order, description
)
VALUES
    ('exclude_program_manager', 'excluded', 'exclude', 'program manager', 1,
     'Exclude Program Manager; Technical Program Manager remains eligible.'),
    ('product_manager', 'product_manager', 'contains', 'product manager', 10,
     'Product Manager and variants such as Senior Product Manager.'),
    ('technical_product_manager', 'product_manager', 'contains', 'technical product manager', 11,
     'Technical Product Manager.'),
    ('project_manager', 'project_manager', 'contains', 'project manager', 20,
     'Project Manager and variants.'),
    ('it_project_manager', 'project_manager', 'contains', 'it project manager', 21,
     'IT Project Manager.'),
    ('technical_project_manager', 'project_manager', 'contains', 'technical project manager', 22,
     'Technical Project Manager.'),
    ('information_technology_project_manager', 'project_manager', 'contains',
     'information technology project manager', 23,
     'Information Technology Project Manager and titles containing Information Technology Project Managers.'),
    ('technical_program_manager', 'technical_program_manager', 'contains',
     'technical program manager', 30, 'Technical Program Manager.'),
    ('solution_architect', 'architect', 'contains', 'solution architect', 40,
     'Solution Architect.'),
    ('solutions_architect', 'architect', 'contains', 'solutions architect', 41,
     'Solutions Architect.'),
    ('technical_architect', 'architect', 'contains', 'technical architect', 42,
     'Technical Architect.'),
    ('technology_architect', 'architect', 'contains', 'technology architect', 43,
     'Technology Architect.'),
    ('systems_engineer', 'engineer', 'contains', 'systems engineer', 50,
     'Systems Engineer.'),
    ('system_engineer', 'engineer', 'contains', 'system engineer', 51,
     'System Engineer.'),
    ('system_engineers', 'engineer', 'contains', 'system engineers', 52,
     'System Engineers.'),
    ('sales_engineer', 'engineer', 'contains', 'sales engineer', 53,
     'Sales Engineer.'),
    ('technology_consultant', 'consultant', 'contains', 'technology consultant', 60,
     'Technology Consultant.'),
    ('solutions_consultant', 'consultant', 'contains', 'solutions consultant', 61,
     'Solutions Consultant.'),
    ('scrum_master', 'agile', 'contains', 'scrum master', 70,
     'Scrum Master.');

CREATE OR REPLACE FUNCTION jobpush.is_product_role_job_title(title TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    WITH normalized AS (
        SELECT LOWER(COALESCE(title, '')) AS value
    ),
    excluded AS (
        SELECT EXISTS (
            SELECT 1
            FROM jobpush.product_role_title_rules rule
            CROSS JOIN normalized
            WHERE rule.active
              AND rule.match_kind = 'exclude'
              AND normalized.value LIKE '%' || LOWER(rule.pattern) || '%'
              AND NOT (
                  rule.pattern = 'program manager'
                  AND normalized.value LIKE '%technical program manager%'
              )
        ) AS is_excluded
    ),
    included AS (
        SELECT EXISTS (
            SELECT 1
            FROM jobpush.product_role_title_rules rule
            CROSS JOIN normalized
            WHERE rule.active
              AND rule.match_kind = 'contains'
              AND normalized.value LIKE '%' || LOWER(rule.pattern) || '%'
        ) AS is_included
    )
    SELECT included.is_included AND NOT excluded.is_excluded
    FROM included, excluded;
$$;

CREATE OR REPLACE FUNCTION jobpush.product_role_job_title_category(title TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT rule.category
    FROM jobpush.product_role_title_rules rule
    WHERE rule.active
      AND rule.match_kind = 'contains'
      AND LOWER(COALESCE(title, '')) LIKE '%' || LOWER(rule.pattern) || '%'
      AND jobpush.is_product_role_job_title(title)
    ORDER BY rule.sort_order
    LIMIT 1;
$$;

ALTER TABLE jobpush.company_targets
    ADD COLUMN IF NOT EXISTS product_role_score NUMERIC(3, 1) NOT NULL DEFAULT 0;

ALTER TABLE jobpush.company_targets
    DROP CONSTRAINT IF EXISTS company_targets_product_role_score_check;

ALTER TABLE jobpush.company_targets
    ADD CONSTRAINT company_targets_product_role_score_check
    CHECK (product_role_score >= 0);

COMMIT;
