BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.chicago_metro_cities (
    city_name TEXT PRIMARY KEY
);

INSERT INTO jobpush.chicago_metro_cities (city_name)
VALUES
    ('Arlington Heights'),
    ('Aurora'),
    ('Bolingbrook'),
    ('Chicago'),
    ('Des Plaines'),
    ('Downers Grove'),
    ('Evanston'),
    ('Glenview'),
    ('Hoffman Estates'),
    ('Joliet'),
    ('Mount Prospect'),
    ('Naperville'),
    ('Oak Brook'),
    ('Orland Park'),
    ('Palatine'),
    ('Schaumburg'),
    ('Skokie'),
    ('Tinley Park'),
    ('Wheaton')
ON CONFLICT (city_name) DO NOTHING;

CREATE OR REPLACE FUNCTION jobpush.is_chicago_metro(employer_city TEXT, employer_state TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT UPPER(TRIM(COALESCE(employer_state, ''))) = 'IL'
       AND EXISTS (
            SELECT 1
            FROM jobpush.chicago_metro_cities metro
            WHERE LOWER(TRIM(COALESCE(employer_city, ''))) = LOWER(metro.city_name)
       );
$$;

ALTER TABLE jobpush.company_targets
    RENAME COLUMN role_match_score TO target_role_score;

ALTER TABLE jobpush.company_targets
    DROP CONSTRAINT IF EXISTS company_targets_role_match_score_check;

ALTER TABLE jobpush.company_targets
    DROP COLUMN IF EXISTS target_role_match;

ALTER TABLE jobpush.company_targets
    ALTER COLUMN target_role_score TYPE NUMERIC(3, 1)
    USING target_role_score::NUMERIC(3, 1);

ALTER TABLE jobpush.company_targets
    ADD COLUMN IF NOT EXISTS lca_count_score NUMERIC(3, 1) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS chicago_score NUMERIC(3, 1) NOT NULL DEFAULT 0;

ALTER TABLE jobpush.company_targets
    ALTER COLUMN priority_score TYPE NUMERIC(4, 1)
    USING priority_score::NUMERIC(4, 1);

ALTER TABLE jobpush.company_targets
    ADD CONSTRAINT company_targets_target_role_score_check
    CHECK (target_role_score >= 0),
    ADD CONSTRAINT company_targets_lca_count_score_check
    CHECK (lca_count_score >= 0),
    ADD CONSTRAINT company_targets_chicago_score_check
    CHECK (chicago_score >= 0),
    ADD CONSTRAINT company_targets_priority_score_check
    CHECK (priority_score >= 0);

COMMIT;
