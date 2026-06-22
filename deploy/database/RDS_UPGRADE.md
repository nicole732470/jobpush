# RDS upgrade notes (shared JobLens + JobPush)

The production database is `joblens-db` in `us-east-2`, currently `db.t4g.micro`.

JobPush refresh workloads scan all of `public.lca_cases` once per full rebuild.
On `t4g.micro` that scan is the main bottleneck even after migration 019.

## Recommendation

| Instance | vCPU / RAM | When |
|---|---|---|
| `db.t4g.small` | 2 / 2 GiB | Minimum uplift for faster refresh |
| `db.t4g.medium` | 2 / 4 GiB | Comfortable headroom for JobLens + JobPush |

## Procedure (coordinate with JobLens)

1. Announce a short maintenance window (typically under 5 minutes downtime for modify).
2. In AWS Console → RDS → `joblens-db` → **Modify**.
3. Change **DB instance class** to `db.t4g.small` (or `medium`).
4. Apply **immediately** or during the agreed window.
5. After upgrade, run a benchmark:

   ```bash
   bash db/refresh/run_refresh_pipeline.sh --only filing-stats
   ```

## What JobPush does not do automatically

- JobPush migrations do **not** resize RDS.
- JobPush does **not** drop `public` indexes without JobLens approval.

## Cost note

`t4g.small` is roughly 2× the micro hourly rate. For a shared production DB
serving both products, the extra cost is usually justified by shorter refresh
cycles and lower risk of OOM during concurrent JobLens traffic.
