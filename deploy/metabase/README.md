# JobPush Metabase

Metabase runs as `jobpush-metabase` on the existing JobLens EC2 instance. It
binds only to `127.0.0.1:3000`; RDS and Metabase are not exposed publicly.

## Cost and resources

- No additional EC2 or RDS instance was created.
- The existing `t3.small` has 2 GB RAM. Metabase is limited to 1 GB with a
  768 MB Java heap, and the host has a 2 GB swap file as an OOM safety net.
- This is suitable for one-person, light dashboard use. Upgrade the instance
  before adding concurrent users or heavy queries.

## Database separation

- `metabaseappdb` stores Metabase users, questions, dashboards, and settings.
- `metabase_reader` is the analytics connection. It has read-only access only
  to company, LCA, sponsorship-resolution, website, and JobPush tables.
- Credentials are stored in AWS Secrets Manager as `jobpush/metabase`; no
  passwords are committed to GitHub.

## First-time setup

Double-click `first-time-setup.command`. It prints the non-secret PostgreSQL
connection fields, copies the read-only database password to the clipboard,
opens an encrypted SSM tunnel, and launches the setup page. Create your own
Metabase administrator account, then paste the copied password when adding the
`JobPush Data` PostgreSQL database.

## Open Metabase after setup

Double-click `open-metabase.command`. It opens an encrypted AWS SSM tunnel and
then opens `http://localhost:3000` in the browser. Keep the terminal window open
while using Metabase.

## Operations

```bash
docker ps --filter name=jobpush-metabase
docker logs --tail 100 jobpush-metabase
curl http://127.0.0.1:3000/api/health
```

Official references:

- https://www.metabase.com/docs/latest/installation-and-operation/running-metabase-on-docker
- https://www.metabase.com/docs/latest/installation-and-operation/configuring-application-database
