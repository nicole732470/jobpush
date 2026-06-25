# JobPush → Codex 交接说明

最后更新：2026-06-24
仓库：`https://github.com/nicole732470/jobpush.git`，分支 **`main`**  
生产 RDS 已部署 migration **001–072**；另外有 repeatable ops scripts for
Tavily quota reset / career-site auto-trust / usage checks。

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
| `jobpush.career_site_selection_candidates` | 每个候选站点的可解释选择分数和决定；人工结论优先 |
| `jobpush.company_priority_enrichment_workbench` | priority + 历史 Tavily 证据 + 可选公司画像的分析视图 |
| `jobpush.company_targets` | 每 FEIN 审计表（`priority-v7`），非 crawl 队列 |
| `jobpush.employer_filing_stats` | 物化层：一次扫 `lca_cases` 得到的 per-FEIN 聚合 |
| `jobpush.company_consolidation_*` | 保守多 FEIN 合并（Amazon、Apple 等） |
| `jobpush.linkedin_top_employer_*` | LinkedIn 2026 Top Employers 匹配与打分 |
| `jobpush.product_role_title_rules` | Product 类 job title 规则 |
| `jobpush.target_soc_roles` | 97 个目标 SOC 码 |
| `jobpush.profile_title_rule_terms` | JobPush title 推荐规则表；`profile-title-rules-v2` 从这里读取 target / avoid 规则 |
| `jobpush.job_title_ai_classifications` | 可选实验性 AI 审计表；默认不依赖付费模型且永不覆盖 manual |

行数（约，2026-06-22）：consolidated **68,958**；employer_filing_stats **69,250**。

2026-06-24 更新：dashboard 默认只展示 `target` jobs。`review` 是 classifier
审计池，不是 Nicole 每天要投递的推荐池。

2026-06-24 后续更新：priority-v9 将仅有 1–2 条 LCA 且全部为明确高管职位的
公司置 0 分并退出 crawl queue。职位泛化优先使用 migration 072 的本地监督学习
（人工 label + 5-fold holdout + 98% precision gate），不依赖付费 AI API。

2026-06-25 更新：Tavily career-site discovery 已累计成功搜索 2,903 家、
保留 7,251 个候选 URL；这不是 2,903 家都已可爬。P1 当前 724 家有
verified/crawl-enabled site，2,105 家有候选待后续规则/人工/泛化处理，
1,756 家仍 pending discovery。AWS Secret 中当前 Tavily key usage
为 1000/1000 时会返回 HTTP 432；不要继续跑大批次，先 rotate key。

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
| **P0** | **仅手动**；写入 `crawl_priority_overrides`，refresh 不会覆盖 |
| `NULL` | 其余（0、1、2、2.25 等） |

生产占比（全表 68,958）：

- **P0**：7（Salesforce、Cognizant主美国实体、Google、Alphabet/Google、HERE、Grubhub Holdings Inc.、JPMorgan Chase & Co.）
- **P1**：4,650（6.74%）
- **P2**：14,487（21.01%）
- 未分档：49,816（72.24%）

在有目标岗公司（41,360）中：P1 **11.3%**，P2 **35.0%**。

手动override：

```sql
INSERT INTO jobpush.crawl_priority_overrides
    (consolidation_key, override_tier, reason, created_by)
VALUES ('FEIN 或 group_id', 'P0', '原因', 'nicole')
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    active = TRUE,
    updated_at = now();
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
| 026 | 持久人工P档override；区分computed与effective tier |
| 027 | 将旧Google/Alphabet直接P0设置迁移到持久override表 |
| 028 | Baker Hughes从自动P1人工降至有效P2 |
| 029 | HERE改P0并确认正确iCIMS招聘搜索URL |

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
4. **P0/P2人工档位**：统一写 `crawl_priority_overrides`；sync 自动更新 `crawl_targets`。
5. **Crawl 生产链路**：iCIMS、Greenhouse、Workday、Oracle Cloud、Apple adapters
   已接入 GitHub Actions 小时级调度（OIDC → SSM → EC2）；P0/P1/P2 实际频率为 24/72/168 小时。继续人工审核
   官网，只有 verified + US-ready + supported adapter 才进入调度。
   官网人工审核只使用 `career_site_review_workbench`；它把pending + verified整合为
   一张公司级视图，P0/潜在P0优先，Google等verified P0不会消失。Migration 057
   已删除其余重复人工queue。2026-06-23 已先搜索150家公司/381候选，再增加50家潜在P0混合样本/123候选。
6. **职位人工标注**：SOC 精确匹配已自动分类；剩余 7,100 个 detailed titles 在
   `job_title_review_queue`，先处理导出表中的 171 个 HIGH 标题。
   HIGH已于2026-06-23全部标注并导入（37 target / 133 non-target / 1 review）。
   共享画像仍为draft；普通用户API保持原格式，owner-only学习字段不进入表单/用户JSON。
   首次规则与官网精度抽检计划为2026-06-30，详见 `LEARNING_OPERATIONS.md`。
7. **Amazon JC 类 title**：是否纳入 product engineer 类别，曾讨论未决。
8. **`per-FEIN company_targets`**：可改为 nightly-only 以省 refresh 时间（可选）。

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
