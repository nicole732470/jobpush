# JobPush → Codex 交接说明

最后更新：2026-06-22  
仓库：`https://github.com/nicole732470/jobpush.git`，分支 **`main`**  
生产 RDS 已与本文描述的 migration **001–022** 对齐部署。

---

## 1. 项目是做什么的

**JobPush** 从共享 LCA 数据里挑出值得爬 career site 的雇主，按可解释的分数排序 crawl。

- **JobLens** 拥有 `public.*`（公司、LCA、网站等），是线上产品数据源。
- **JobPush** 只拥有 **`jobpush` schema**，读 `public`，写 `jobpush`。
- **不要**改 `public` 表结构、索引或 JobLens 应用逻辑；任何共享库优化需与 JobLens 协调。

---

## 2. 基础设施

| 资源 | 值 |
|---|---|
| RDS | `joblens-db`，`us-east-2`，**`db.t4g.micro`**（偏小，refresh 慢） |
| 数据库名 | `joblens` |
| 凭证 | AWS Secrets Manager `joblens/rds` |
| EC2（SSM） | `i-0bdee6f611283586f` |
| 本地连库 | 双击 `deploy/database/open-database.command` → TablePlus `127.0.0.1:15432` |

RDS **在 VPC 内**，本机不能直接 `psql`。部署用：

```bash
bash db/deploy_via_ssm.sh db/run_migration_XXX.sh
bash db/deploy_via_ssm.sh db/refresh/run_refresh_pipeline.sh
```

`db/lib/connect_rds.sh` 供 shell 脚本复用 RDS 连接。

---

## 3. 核心表：先看哪张

| 表 | 用途 |
|---|---|
| **`jobpush.company_targets_consolidated`** | **公司分析与P档来源表**（合并品牌 + 单 FEIN），含 `priority_score`、`crawl_priority_tier` |
| **`jobpush.crawl_targets`** | **Crawler 运行队列**；从 consolidated 同步 P0/P1/P2，保留发现状态 |
| **`jobpush.career_sites`** | 一个公司可对应多个真实 corporate/career/ATS 站点及抓取状态 |
| `jobpush.company_targets` | 每 FEIN 审计表（`priority-v7`），非 crawl 队列 |
| `jobpush.employer_filing_stats` | 物化层：一次扫 `lca_cases` 得到的 per-FEIN 聚合 |
| `jobpush.company_consolidation_*` | 保守多 FEIN 合并（Amazon、Apple 等） |
| `jobpush.linkedin_top_employer_*` | LinkedIn 2026 Top Employers 匹配与打分 |
| `jobpush.product_role_title_rules` | Product 类 job title 规则 |
| `jobpush.target_soc_roles` | 97 个目标 SOC 码 |

行数（约，2026-06-22）：consolidated **68,958**；employer_filing_stats **69,250**。

---

## 4. 打分模型（`priority-v8-consolidated`）

```text
priority_score =
  target_role_score          (+1  有目标 SOC)
+ lca_count_score            (+1  目标岗且 lca_count>1)
+ chicago_score              (+0.5 芝加哥 metro)
+ product_role_score         (+1  产品类 title)
+ product_manager_score      (+0.25 PM / Technical PM)
+ salary_score               (+1  目标岗最低有效年薪 ≥ $90k)
+ linkedin_top_employer_score (+1  保守匹配 LinkedIn 2026)
```

满分 **5.75**。细节见 [`PRIORITY.md`](PRIORITY.md)。

### Crawl 档位 `crawl_priority_tier`（migration 022）

| 档位 | 规则 |
|---|---|
| **P1** | `priority_score > 3`（3.25、4.0、5.25 等） |
| **P2** | `priority_score IN (3.0, 2.5)` |
| **P0** | **仅手动**；refresh 时保留，不会被覆盖 |
| `NULL` | 其余（0、1、2、2.25 等） |

生产占比（全表 68,958）：

- **P1**：4,656（6.75%）
- **P2**：14,486（21.01%）
- 未分档：49,816（72.24%）

在有目标岗公司（41,360）中：P1 **11.3%**，P2 **35.0%**。

手动标 P0：

```sql
UPDATE jobpush.company_targets_consolidated
SET crawl_priority_tier = 'P0', updated_at = now()
WHERE consolidation_key = 'FEIN 或 group_id';
```

---

## 5. Refresh 架构（migration 019 之后）

```text
public.lca_cases  ──(一次扫描 ~5min)──>  jobpush.employer_filing_stats
                                                │
                         company_targets (audit) │ company_targets_consolidated (crawl)
```

```bash
# 全量（新 LCA 数据 / wage repair 后）
bash db/deploy_via_ssm.sh db/refresh/run_refresh_pipeline.sh

# 只改 LinkedIn / 合并规则（跳过 lca 扫描）
bash db/deploy_via_ssm.sh db/refresh/run_refresh_pipeline.sh --skip-filing-stats --skip-per-fein

# 只刷新 consolidated（filing stats 已新）
bash db/deploy_via_ssm.sh db/run_refresh_consolidated_benchmark.sh
```

实测 `t4g.micro`：filing stats ~5min；consolidated **~8s**（已优化 EXISTS）。

见 [`PERFORMANCE.md`](PERFORMANCE.md)、[`deploy/database/RDS_UPGRADE.md`](../deploy/database/RDS_UPGRADE.md)。

---

## 6. 配置文件（改规则后需 reload + refresh）

| 文件 | 作用 |
|---|---|
| `config/company_consolidation_policies.csv` | 合并策略 `merge_all` / `merge_strict` / `skip` |
| `config/company_consolidation_name_denies.csv` | 合并误匹配 deny |
| `config/linkedin_top_employers_2026.csv` | LinkedIn 名单 |
| `config/linkedin_top_employer_match_terms.csv` | 品牌匹配 key |
| `config/linkedin_top_employer_scoring_excludes.csv` | **永不打分**的模糊品牌（abstract/vast/abridge） |
| `config/product_role_title_rules.csv` | Product title 规则 |

生成脚本：`scripts/build_linkedin_top_employers_2026.py` 等。

LinkedIn 保守匹配（migration 021）：

- `linkedin_top_employer_scoring_excludes` + `company_consolidation_policies.skip`
- `merge_strict` 品牌需 `name_allow_regex` 才匹配
- 函数：`jobpush.linkedin_top_employer_match_confident()`

---

## 7. Migration 清单（011–022，近期）

| # | 内容 |
|---|---|
| 011–013 | `product_role_lca_pct`；`product_role_pct_score` 实验后回滚 |
| 014 | `product_manager_score`；`lca_count>1` |
| 015 | LinkedIn 2026 打分 |
| 016 | 公司合并 + `company_targets_consolidated` |
| 017 | consolidated `salary_score` |
| 018 | FY2025 Q1 wage repair（`public.lca_cases` 数据修正，schema 不变） |
| 019 | **`employer_filing_stats`** 物化层 |
| 020 | 可选删除 wage repair staging 表（仅 jobpush） |
| 021 | LinkedIn 匹配置信度 / 排除模糊品牌 |
| 022 | **`crawl_priority_tier`** P0/P1/P2 |
| 023 | **`crawl_targets` + `career_sites`** crawler 运行层及同步 |
| 024 | 4.5+ 官网候选发现、候选证据和 search run 审计 |
| 025 | 聚合站排除、TablePlus 人工审核视图和确认/拒绝函数 |

每个 migration 通常有 `db/run_migration_NNN.sh`；通过 `db/deploy_via_ssm.sh` 在 EC2 执行。

---

## 8. 分析用 SQL（只读）

| 脚本 | 作用 |
|---|---|
| `db/analysis/priority_distribution_and_linkedin_audit.sql` | 分数分布、LinkedIn 审计 |
| `db/analysis/priority_score_2_and_3_breakdown.sql` | 2 分 / 3 分组成 |
| `db/analysis/priority_score_225_and_25_breakdown.sql` | 2.25 / 2.5 组成 |
| `db/analysis/priority_225_salary_check.sql` | 2.25 薪资明细 |

```bash
bash db/deploy_via_ssm.sh db/run_priority_audit.sh
```

---

## 9. 分数分布速查（consolidated，2026-06-22）

| priority_score | 公司数 | 典型组成 |
|---:|---:|---|
| 0 | 27,598 | 无目标岗 |
| 2.0 | 17,526 | target + lca **或** target + salary |
| 3.0 | 13,942 | target + lca + salary（75%）或 + product（21%） |
| 2.5 | 544 | target + **chicago** + lca 或 + salary |
| 2.25 | 26 | target + product + PM，薪资均 &lt; $90k |
| 4.0+ | ~1,300 | 多项叠加 |
| 最高 5.25 | 5 | 缺 chicago 0.5 可达的顶分案例 |

---

## 10. 已知问题与待办

1. **RDS 实例过小**：`t4g.micro`；filing stats 全表扫描仍 ~5min。可与 JobLens 协调升 `t4g.small`。
2. **`public.lca_cases` 大索引**：JobPush 不会自动删；见 [`JOBLENS_SHARED_INDEX_NOTES.md`](JOBLENS_SHARED_INDEX_NOTES.md)。
3. **Wage repair staging**：`lca_wage_repair_stage` / `backup` 仍在 RDS；验证后可 `bash db/run_migration_020.sh`。
4. **P0 名单**：用户将手动标；sync 会自动加入 `crawl_targets`。
5. **Crawl 实现**：4.5+ 候选已生成并等待人工审核；ATS adapter 和定时 worker 待实现。
6. **Amazon JC 类 title**：是否纳入 product engineer 类别，曾讨论未决。
7. **`per-FEIN company_targets`**：可改为 nightly-only 以省 refresh 时间（可选）。

---

## 11. Git / 协作约定

- 远程：**`origin/main`**
- **一个功能一个 commit**，改完就 push（用户偏好）
- **不要** force push main；不要改 git config
- 文档：[`DATABASE.md`](DATABASE.md)、[`PRIORITY.md`](PRIORITY.md)、[`COMPANY_CONSOLIDATION.md`](COMPANY_CONSOLIDATION.md)、[`LINKEDIN_TOP_EMPLOYERS.md`](LINKEDIN_TOP_EMPLOYERS.md)、[`LCA_WAGE_REPAIR.md`](LCA_WAGE_REPAIR.md)

---

## 12. JobLens 安全红线

- JobPush migration / refresh **只写 `jobpush.*`**
- 可读 `public.companies`、`public.lca_cases`（与之前相同）
- 018 wage repair **改的是 `public.lca_cases` 数据**（非 schema），已与 JobLens 共享；有 `jobpush.lca_wage_repair_backup` 审计
- 不要在未协调的情况下 drop `public` 索引或 resize RDS

---

## 13. 建议 Codex 上手顺序

1. 读 `README.md`、`docs/PRIORITY.md`、`docs/DATABASE.md`
2. TablePlus 打开 `jobpush.company_targets_consolidated`，按 `crawl_priority_tier`、`priority_score` 排序浏览
3. 跑只读 audit：`bash db/deploy_via_ssm.sh db/run_priority_audit.sh`
4. 改 config 时：load SQL → rebuild matches/members → `run_refresh_pipeline.sh --skip-filing-stats`（视情况）
5. 新 schema：加 `db/migrations/023_*.sql` + `db/run_migration_023.sh`，用 `deploy_via_ssm.sh` 部署

---

## 14. 关键文件索引

```text
db/refresh/refresh_employer_filing_stats.sql      # 唯一 lca_cases 全扫
db/refresh/refresh_company_targets_consolidated.sql  # crawl 队列 + 打分 + tier
db/refresh/rebuild_linkedin_top_employer_matches.sql
db/refresh/rebuild_company_consolidation_members.sql
db/refresh/run_refresh_pipeline.sh
db/deploy_via_ssm.sh
docs/PRIORITY.md
docs/PERFORMANCE.md
```

有问题先查 agent 历史或本文件；生产数据以 RDS 为准，文档中的数字为 2026-06-22 快照。
