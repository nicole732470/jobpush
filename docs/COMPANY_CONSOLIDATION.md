# Company consolidation (dedup)

Large brands often appear as many legal FEINs in LCA data. JobPush keeps the
original per-FEIN `jobpush.company_targets` unchanged, and adds a conservative
**consolidated** layer for crawl prioritization.

## Tables

| Table | Purpose |
|---|---|
| `jobpush.company_consolidation_policies` | When to merge (per LinkedIn employer key) |
| `jobpush.company_consolidation_name_denies` | Global false-positive name patterns |
| `jobpush.company_consolidation_groups` | A merged brand group (2+ FEINs) |
| `jobpush.company_consolidation_members` | FEINs inside each group |
| `jobpush.company_targets_consolidated` | Scores recomputed on merged LCA data |

## Policies

| Policy | Meaning |
|---|---|
| `merge_all` | All LinkedIn-matched FEINs for the brand, minus global deny patterns |
| `merge_strict` | Only FEINs whose legal name matches `name_allow_regex` |
| `skip` | Do not merge (ambiguous short brands) |

Examples:

- **Amazon / Apple / Fidelity** → `merge_all`
- **Sage** → `merge_strict` → only Sage Software, Sage Intacct, Sage Group Technologies
- **Vast / Abstract / Abridge** → `skip`

Config files:

- `config/company_consolidation_policies.csv`
- `config/company_consolidation_name_denies.csv`

## How scores are merged

Consolidated rows **re-aggregate all LCA filings** across member FEINs, then
recompute component scores (not a simple MAX on old per-FEIN scores).

Union behavior the user asked for falls out naturally:

- If any member has product-class titles → group `product_role_score = 1`
- If any member is in Chicago metro → group `chicago_score = 0.5`
- If the minimum valid annualized target-role salary across members is at least
  $90,000 → group `salary_score = 1`
- If any member matched LinkedIn top employers and the group has a target role →
  group `linkedin_top_employer_score = 1`
- `lca_count`, `target_role_lca_count`, `product_role_lca_count` are **summed**

Singleton companies (not merged into any group) still appear in
`company_targets_consolidated` as one FEIN = one row.

## Refresh

```bash
bash db/run_migration_016.sh
```

Or, after editing policies:

```bash
psql ... -f db/refresh/rebuild_company_consolidation_members.sql
psql ... -f db/refresh/refresh_company_targets_consolidated.sql
```

## Sage example

Before consolidation Sage matching had 22 FEINs. After `merge_strict`, only:

- Sage Software Inc.
- Sage Intacct, Inc.
- SAGE GROUP TECHNOLOGIES INC

are merged into one `sage` group. Unrelated names (Sage Therapeutics, SAGE IT INC,
etc.) stay as separate singleton rows.
