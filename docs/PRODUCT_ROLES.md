# Product-class job titles

Product-class roles are matched against the raw LCA `job_title` field only.
They do not use `soc_title` or normalized mapping titles.

Rules live in `jobpush.product_role_title_rules` and are evaluated by
`jobpush.is_product_role_job_title(job_title)`.

## Scoring

- `product_role_score = 1` only when `target_role_score = 1` and the company has
  at least one LCA row whose raw `job_title` matches a product-class rule.
- `product_role_score = 0` otherwise.
- `product_role_lca_count` stores how many of the company's LCA filings match a
  product-class rule.
- `product_role_lca_pct` stores the in-company share:
  `100 * product_role_lca_count / lca_count`.
- `priority_score` includes `product_role_score` and `product_manager_score`
  in the total. See [`PRIORITY.md`](PRIORITY.md).

Product Manager matching uses `jobpush.is_product_manager_job_title(job_title)`
(category `product_manager` in `jobpush.product_role_title_rules`).

## Included patterns

| Category | Raw `job_title` contains | Notes |
|---|---|---|
| `product_manager` | `product manager` | Includes Senior Product Manager, etc. |
| `product_manager` | `technical product manager` | |
| `project_manager` | `project manager` | |
| `project_manager` | `it project manager` | |
| `project_manager` | `technical project manager` | |
| `project_manager` | `information technology project manager` | Also matches titles containing `Information Technology Project Managers` |
| `technical_program_manager` | `technical program manager` | |
| `architect` | `solution architect` | |
| `architect` | `solutions architect` | |
| `architect` | `technical architect` | |
| `architect` | `technology architect` | |
| `engineer` | `systems engineer` | |
| `engineer` | `system engineer` | |
| `engineer` | `system engineers` | |
| `engineer` | `sales engineer` | |
| `consultant` | `technology consultant` | |
| `consultant` | `solutions consultant` | |
| `agile` | `scrum master` | |

## Excluded patterns

| Pattern | Notes |
|---|---|
| `program manager` | Explicitly excluded. `Technical Program Manager` remains eligible. |

## Explicitly not included in v1

- `Program Manager` by itself
- Amazon JC titles such as `Manager JC50 - Computer Systems Engineers/Architects`
  unless the raw title itself contains one of the included phrases above

## Maintenance

Edit `jobpush.product_role_title_rules`, then rerun
`db/refresh/refresh_company_targets.sql`.

Category lookup for analysis:
`jobpush.product_role_job_title_category(job_title)`.
