#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -qAt -c "\copy (
    WITH distinct_companies AS (
        SELECT DISTINCT posting.normalized_title, target.canonical_name
        FROM jobpush.job_postings posting
        JOIN jobpush.crawl_targets target USING (consolidation_key)
        WHERE posting.active AND posting.market_scope = 'US'
    ), ranked AS (
        SELECT normalized_title, canonical_name,
               row_number() OVER (
                   PARTITION BY normalized_title ORDER BY canonical_name
               ) AS company_rank
        FROM distinct_companies
    ), examples AS (
        SELECT normalized_title,
               string_agg(canonical_name, ' | ' ORDER BY canonical_name) AS example_companies
        FROM ranked
        WHERE company_rank <= 3
        GROUP BY normalized_title
    )
    SELECT
        queue.normalized_title,
        queue.example_title,
        queue.active_posting_count,
        queue.company_count,
        COALESCE(examples.example_companies, '') AS example_companies,
        queue.suggestion_reason,
        queue.matched_soc_codes,
        queue.matched_soc_titles,
        ''::text AS \"人工判断（请填写）\",
        ''::text AS \"标准岗位（可选）\",
        ''::text AS \"判断原因/备注（可选）\"
    FROM jobpush.job_title_review_queue queue
    LEFT JOIN examples USING (normalized_title)
    ORDER BY queue.active_posting_count DESC, queue.company_count DESC, queue.normalized_title
    LIMIT 500
) TO STDOUT WITH CSV HEADER"
