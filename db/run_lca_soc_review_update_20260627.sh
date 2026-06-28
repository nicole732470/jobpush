#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

REVIEW_CSV="$REPO_DIR/config/lca_soc_review_20260627.csv"

if [[ ! -f "$REVIEW_CSV" ]]; then
  echo "Missing review CSV: $REVIEW_CSV" >&2
  exit 2
fi

"${PSQL[@]}" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

CREATE TABLE IF NOT EXISTS jobpush.lca_soc_role_review_current (
    normalized_soc_code TEXT NOT NULL,
    soc_title TEXT NOT NULL,
    review_status TEXT NOT NULL,
    previous_target BOOLEAN NOT NULL DEFAULT FALSE,
    lca_count INTEGER NOT NULL DEFAULT 0,
    company_count INTEGER NOT NULL DEFAULT 0,
    certified_count INTEGER NOT NULL DEFAULT 0,
    raw_title_count INTEGER NOT NULL DEFAULT 0,
    first_decision_date DATE,
    last_decision_date DATE,
    min_yearly_wage_from NUMERIC(14, 2),
    median_yearly_wage_from NUMERIC(14, 2),
    max_yearly_wage_from NUMERIC(14, 2),
    source_file TEXT NOT NULL DEFAULT 'JobPush_LCA_SOC_RawJob_标注复审_2026-06-27.xlsx',
    reviewed_by TEXT NOT NULL DEFAULT 'nicole',
    reviewed_at DATE NOT NULL DEFAULT DATE '2026-06-28',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (normalized_soc_code, soc_title),
    CHECK (normalized_soc_code ~ '^[0-9]{8}$'),
    CHECK (review_status IN ('target', 'non_target', 'review', ''))
);

CREATE TABLE IF NOT EXISTS jobpush.lca_soc_role_review_stage (
    normalized_soc_code TEXT,
    soc_title TEXT,
    review_status TEXT,
    previous_target TEXT,
    lca_count TEXT,
    company_count TEXT,
    certified_count TEXT,
    raw_title_count TEXT,
    first_decision_date TEXT,
    last_decision_date TEXT,
    min_yearly_wage_from TEXT,
    median_yearly_wage_from TEXT,
    max_yearly_wage_from TEXT
);

TRUNCATE jobpush.lca_soc_role_review_stage;

COMMIT;
SQL

"${PSQL[@]}" -v ON_ERROR_STOP=1 -c "\\copy jobpush.lca_soc_role_review_stage FROM '$REVIEW_CSV' WITH (FORMAT CSV, HEADER TRUE)"

"${PSQL[@]}" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

TRUNCATE jobpush.lca_soc_role_review_current;

INSERT INTO jobpush.lca_soc_role_review_current (
    normalized_soc_code, soc_title, review_status, previous_target,
    lca_count, company_count, certified_count, raw_title_count,
    first_decision_date, last_decision_date,
    min_yearly_wage_from, median_yearly_wage_from, max_yearly_wage_from,
    updated_at
)
SELECT
    normalized_soc_code,
    soc_title,
    COALESCE(NULLIF(BTRIM(review_status), ''), '') AS review_status,
    LOWER(previous_target) = 'true' AS previous_target,
    NULLIF(lca_count, '')::INTEGER,
    NULLIF(company_count, '')::INTEGER,
    NULLIF(certified_count, '')::INTEGER,
    NULLIF(raw_title_count, '')::INTEGER,
    NULLIF(first_decision_date, '')::DATE,
    NULLIF(last_decision_date, '')::DATE,
    NULLIF(min_yearly_wage_from, '')::NUMERIC(14, 2),
    NULLIF(median_yearly_wage_from, '')::NUMERIC(14, 2),
    NULLIF(max_yearly_wage_from, '')::NUMERIC(14, 2),
    now()
FROM jobpush.lca_soc_role_review_stage;

WITH reviewed_targets AS (
    SELECT
        normalized_soc_code,
        (ARRAY_AGG(soc_title ORDER BY lca_count DESC, soc_title))[1] AS representative_title,
        COUNT(DISTINCT soc_title)::INTEGER AS source_code_count,
        COUNT(*)::INTEGER AS selected_title_count
    FROM jobpush.lca_soc_role_review_current
    WHERE review_status = 'target'
    GROUP BY normalized_soc_code
), deactivated AS (
    UPDATE jobpush.target_soc_roles target
    SET active = FALSE,
        updated_at = now()
    WHERE target.active
      AND NOT EXISTS (
          SELECT 1
          FROM reviewed_targets reviewed
          WHERE reviewed.normalized_soc_code = target.normalized_soc_code
      )
    RETURNING target.normalized_soc_code
)
INSERT INTO jobpush.target_soc_roles (
    normalized_soc_code, representative_title, source_code_count,
    selected_title_count, source, active, updated_at
)
SELECT
    normalized_soc_code,
    representative_title,
    source_code_count,
    selected_title_count,
    'JobPush_LCA_SOC_RawJob_标注复审_2026-06-27.xlsx:SOC大类汇总',
    TRUE,
    now()
FROM reviewed_targets
ON CONFLICT (normalized_soc_code) DO UPDATE SET
    representative_title = EXCLUDED.representative_title,
    source_code_count = EXCLUDED.source_code_count,
    selected_title_count = EXCLUDED.selected_title_count,
    source = EXCLUDED.source,
    active = TRUE,
    updated_at = now();

COMMIT;

SELECT review_status, COUNT(*) AS soc_title_rows
FROM jobpush.lca_soc_role_review_current
GROUP BY review_status
ORDER BY review_status;

SELECT active, COUNT(*) AS target_soc_roles
FROM jobpush.target_soc_roles
GROUP BY active
ORDER BY active DESC;
SQL
