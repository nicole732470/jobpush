BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.company_consolidation_policies (
    employer_key       TEXT PRIMARY KEY,
    linkedin_name      TEXT NOT NULL,
    policy             TEXT NOT NULL CHECK (policy IN ('merge_all', 'merge_strict', 'skip')),
    min_feins          INTEGER NOT NULL DEFAULT 2 CHECK (min_feins >= 2),
    name_allow_regex   TEXT,
    name_deny_regex    TEXT,
    notes              TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS jobpush.company_consolidation_name_denies (
    deny_pattern       TEXT PRIMARY KEY,
    notes              TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS jobpush.company_consolidation_groups (
    group_id               TEXT PRIMARY KEY,
    canonical_name         TEXT NOT NULL,
    linkedin_employer_key  TEXT
                           REFERENCES jobpush.linkedin_top_employers_2026(employer_key),
    policy                 TEXT NOT NULL,
    member_fein_count      INTEGER NOT NULL DEFAULT 0 CHECK (member_fein_count >= 2),
    notes                  TEXT NOT NULL DEFAULT '',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS jobpush.company_consolidation_members (
    group_id        TEXT NOT NULL
                    REFERENCES jobpush.company_consolidation_groups(group_id)
                    ON DELETE CASCADE,
    fein            TEXT NOT NULL
                    REFERENCES public.companies(fein) ON DELETE CASCADE,
    company_name    TEXT NOT NULL,
    lca_count       INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (group_id, fein)
);

CREATE INDEX IF NOT EXISTS idx_company_consolidation_members_fein
    ON jobpush.company_consolidation_members(fein);

CREATE TABLE IF NOT EXISTS jobpush.company_targets_consolidated (
    consolidation_key          TEXT PRIMARY KEY,
    canonical_name             TEXT NOT NULL,
    is_merged_group            BOOLEAN NOT NULL DEFAULT FALSE,
    linkedin_employer_key      TEXT,
    member_fein_count          INTEGER NOT NULL DEFAULT 1 CHECK (member_fein_count >= 1),
    member_feins               TEXT[] NOT NULL DEFAULT '{}',
    primary_fein               TEXT,
    employer_city              TEXT,
    employer_state             TEXT,
    naics_code                 TEXT,
    naics_sector               TEXT,
    lca_count                  INTEGER NOT NULL DEFAULT 0,
    certified_count            INTEGER NOT NULL DEFAULT 0,
    single_lca_company         BOOLEAN NOT NULL DEFAULT FALSE,
    target_role_lca_count      INTEGER NOT NULL DEFAULT 0,
    product_role_lca_count     INTEGER NOT NULL DEFAULT 0,
    product_role_lca_pct       NUMERIC(5, 2) NOT NULL DEFAULT 0,
    last_decision_date         DATE,
    recent_lca                 BOOLEAN NOT NULL DEFAULT FALSE,
    target_role_score          NUMERIC(3, 1) NOT NULL DEFAULT 0,
    lca_count_score            NUMERIC(3, 1) NOT NULL DEFAULT 0,
    chicago_score              NUMERIC(3, 1) NOT NULL DEFAULT 0,
    product_role_score         NUMERIC(3, 1) NOT NULL DEFAULT 0,
    product_manager_score      NUMERIC(4, 2) NOT NULL DEFAULT 0,
    linkedin_top_employer_score NUMERIC(3, 1) NOT NULL DEFAULT 0,
    priority_score             NUMERIC(4, 2) NOT NULL DEFAULT 0,
    priority_version           TEXT NOT NULL DEFAULT 'priority-v7-consolidated',
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (product_role_lca_pct >= 0 AND product_role_lca_pct <= 100),
    CHECK (priority_score >= 0)
);

CREATE INDEX IF NOT EXISTS idx_company_targets_consolidated_priority
    ON jobpush.company_targets_consolidated(priority_score DESC, last_decision_date DESC NULLS LAST);

COMMIT;
