"""Create the isolated Metabase application DB and read-only analytics role."""

import json
import os

import psycopg
from psycopg import sql


with open("/tmp/metabase-secret.json", encoding="utf-8") as handle:
    secret = json.load(handle)

admin_url = os.environ["DATABASE_URL"]
app_user = secret["app_db_user"]
app_password = secret["app_db_password"]
app_database = secret["app_db_name"]
reader_user = secret["analytics_db_user"]
reader_password = secret["analytics_db_password"]

admin = psycopg.connect(admin_url, autocommit=True)

for role, password in ((app_user, app_password), (reader_user, reader_password)):
    if not admin.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (role,)).fetchone():
        admin.execute(
            sql.SQL("CREATE ROLE {} LOGIN PASSWORD {}").format(
                sql.Identifier(role), sql.Literal(password)
            )
        )
    else:
        admin.execute(
            sql.SQL("ALTER ROLE {} LOGIN PASSWORD {}").format(
                sql.Identifier(role), sql.Literal(password)
            )
        )

if not admin.execute("SELECT 1 FROM pg_database WHERE datname = %s", (app_database,)).fetchone():
    admin.execute(
        sql.SQL("CREATE DATABASE {} OWNER {}").format(
            sql.Identifier(app_database), sql.Identifier(app_user)
        )
    )

admin.execute(sql.SQL("GRANT CONNECT ON DATABASE joblens TO {}").format(sql.Identifier(reader_user)))
admin.execute(sql.SQL("GRANT USAGE ON SCHEMA public, jobpush TO {}").format(sql.Identifier(reader_user)))

allowed_tables = (
    "public.companies",
    "public.lca_cases",
    "public.company_aliases",
    "public.company_search_keys",
    "public.company_groups",
    "public.company_group_companies",
    "public.company_websites",
    "jobpush.company_targets",
    "jobpush.target_soc_roles",
)
for table in allowed_tables:
    schema_name, table_name = table.split(".", 1)
    admin.execute(
        sql.SQL("GRANT SELECT ON {}.{} TO {}").format(
            sql.Identifier(schema_name),
            sql.Identifier(table_name),
            sql.Identifier(reader_user),
        )
    )

print("Metabase databases and least-privilege roles are ready")
