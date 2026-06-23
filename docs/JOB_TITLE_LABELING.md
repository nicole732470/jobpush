# Detailed job-title labeling

Official career sites produce much more detailed titles than the historical
LCA/SOC workbook. JobPush therefore uses two layers:

1. Exact normalized-title matches against `soc_role_title_mappings` are
   classified automatically by migration 046.
2. Unmatched or SOC-conflicting titles remain in
   `jobpush.job_title_review_queue` for human review.

## Human workflow

The editable workbook is generated from the production review queue, ordered
by active posting count and company count. Only these columns should be edited:

- `人工判断（请填写）`: `target`, `non_target`, or `review`
- `标准岗位（可选）`
- `判断原因/备注（可选）`

Do not edit `normalized_title`; it is the database key. Start with `HIGH`, then
`MEDIUM`. It is not necessary to label the long tail in one session.

Returned decisions are applied with:

```sql
SELECT jobpush.apply_manual_job_title_label(
    'normalized title', 'target', 'Canonical role', 'Reason', 'nicole'
);
```

Manual decisions use `rule_version = 'manual-v1'`, override automatic rules,
and append an immutable row to `job_title_label_history`.

## Current production snapshot (2026-06-23)

- Automatically classified target titles: 111
- Automatically classified non-target titles: 100
- Remaining review titles: 7,100
- Active postings represented by review titles: 9,560
- First labeling tranche (`HIGH`): 171 titles

The export query is `db/analysis/export_job_title_review.sql`.
