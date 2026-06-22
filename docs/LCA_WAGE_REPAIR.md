# FY2025 Q1 LCA wage repair

## Outcome

The AWS `public.lca_cases` table contained 104,046 FY2025 Q1 rows whose wage
fields were positionally misaligned during the combined-workbook import. The
affected decisions were issued from 2024-10-01 through 2024-12-31.

The official source was the U.S. Department of Labor file
`LCA_Disclosure_Data_FY2025_Q1.xlsx`:

https://www.dol.gov/sites/dolgov/files/ETA/oflc/pdfs/LCA_Disclosure_Data_FY2025_Q1.xlsx

The source contains 107,414 unique cases. All 104,046 affected H-1B rows in the
database matched the official file by `case_number` before any update ran.

## What was wrong

The original DOL file was complete. For example, case
`I-200-24358-566651` contains:

| Field | Official value | Before repair |
|---|---:|---:|
| `wage_rate_of_pay_from` | 105997 | 106000 |
| `wage_rate_of_pay_to` | 106000 | null |
| `wage_unit_of_pay` | Year | 105997 |
| `prevailing_wage` | 105997 | null |

This systematic quarter boundary shows that the defect was in positional
column mapping during the combined import, not missing employer submissions.

## Repair workflow

Run from a machine that can reach RDS (or through an SSM tunnel):

```bash
RDS_HOST=127.0.0.1 RDS_PORT=15432 \
  bash db/run_migration_018.sh /path/to/LCA_Disclosure_Data_FY2025_Q1.xlsx
```

The runner:

1. Streams only the official case-number and wage columns to a compact CSV.
2. Requires exactly 107,414 unique official rows.
3. Requires exactly 104,046 affected database rows and a complete case-number
   match.
4. Copies every old and new wage value to
   `jobpush.lca_wage_repair_backup`.
5. Repairs the 12 wage and prevailing-wage fields in `public.lca_cases`.
6. Recomputes salary fields only for affected consolidated companies.

The targeted refresh updated 18,374 consolidated companies. It replaced the
old full-table score refresh for this repair.

## Post-repair validation

- Repaired rows backed up: 104,046
- Recognized wage units in `public.lca_cases`: 785,687 / 785,687
- Target-role companies without a valid annualized salary: 0
- `salary_score = 1` companies: 23,532
- Incorrect or missed salary scores: 0
- Priority totals inconsistent with component sums: 0
- JobLens backend: healthy; Microsoft sponsorship lookup: matched normally

The official workbook is not committed to GitHub. It remains a reproducible
external source; only the extractor, guarded SQL, and audit records are stored.
