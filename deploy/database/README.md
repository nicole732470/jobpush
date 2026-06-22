# JobPush database access

RDS is private. Use an encrypted SSM tunnel plus a desktop GUI to browse tables
visually.

## Recommended: TablePlus

1. Install once:

```bash
brew install --cask tableplus session-manager-plugin
```

2. Double-click `open-database.command`.

3. TablePlus opens (or connect manually with the printed settings). Password is
   copied to your clipboard on each run.

4. In the left sidebar:

- open database `joblens`
- schema `jobpush`
- table `company_targets`

You get a spreadsheet-style grid with sorting, filtering, and full row counts.
No SQL required for basic browsing.

Useful tables:

| Schema | Table | What it is |
|---|---|---|
| `jobpush` | `company_targets` | One row per company, scores and crawl status |
| `jobpush` | `target_soc_roles` | Selected SOC codes used for scoring |
| `public` | `companies` | Shared employer records |
| `public` | `lca_cases` | LCA filing facts |

5. Keep the terminal window open while using TablePlus. Press Ctrl-C when done.

## Other GUI clients

Any PostgreSQL client works through the same tunnel:

| Field | Value |
|---|---|
| Host | `127.0.0.1` |
| Port | `15432` |
| Database | `joblens` |
| Username / password | AWS secret `joblens/rds` |
| SSL | require |

Examples: DBeaver, pgAdmin, DataGrip.

## Prerequisites

1. AWS CLI configured for `us-east-2`
2. Session Manager plugin

TablePlus installs with Homebrew. The Session Manager plugin needs a one-time
macOS installer:

```bash
brew install --cask tableplus
```

If `brew install --cask session-manager-plugin` fails on sudo, double-click
`install-session-manager.command` instead. It downloads the official Apple
installer and opens it in Finder.

## Troubleshooting

**`password authentication failed for user "joblens"`**

- Delete any old saved `JobPush` connection in TablePlus.
- Run `open-database.command` again so it opens a fresh connection with the
  current password from AWS Secrets Manager.
- Make sure the tunnel terminal window stays open.

**Tunnel does not start**

- Run `install-session-manager.command` first.
- Confirm AWS CLI works: `aws sts get-caller-identity`
