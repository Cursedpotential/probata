#!/usr/bin/env python3
"""One-time provisioning: create the least-privilege read-only Postgres role
Metabase uses to browse the `casebible` catalog (schema raw_duck) on ovh-files,
and drop its generated password onto ovh-app at
/data/probata/secrets/metabase/pg-readonly (mode 600).

Run manually, once, from this tracked path (not from a scratch/temp dir — see
the case-bible require_tracked_code guard). Never prints the generated
password. Idempotent: CREATE ROLE is guarded, GRANTs are all re-runnable.

Byline: Claude Code · Sonnet 5 · 2026-09-14
"""
import os
import secrets
import subprocess
import tempfile

CASEBIBLE_HOST = "100.91.190.107"
CASEBIBLE_CONTAINER = "fgz1n7useplhk0t91uk7k1aw"
CASEBIBLE_DB = "casebible"
SCHEMA = "raw_duck"
ROLE = "metabase_ro"

APP_HOST = "100.72.169.40"
SECRET_DIR = "/data/probata/secrets/metabase"
SECRET_PATH = f"{SECRET_DIR}/pg-readonly"

SSH_KEY = os.path.expanduser("~/.ssh/ovh")


def run(cmd, **kw):
    env = dict(os.environ)
    env["MSYS_NO_PATHCONV"] = "1"
    return subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=30, **kw)


def main():
    pw = secrets.token_urlsafe(24)

    sql = f"""
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '{ROLE}') THEN
      CREATE ROLE {ROLE} LOGIN PASSWORD '{pw}';
   ELSE
      ALTER ROLE {ROLE} LOGIN PASSWORD '{pw}';
   END IF;
END
$$;
GRANT CONNECT ON DATABASE {CASEBIBLE_DB} TO {ROLE};
GRANT USAGE ON SCHEMA {SCHEMA} TO {ROLE};
GRANT SELECT ON ALL TABLES IN SCHEMA {SCHEMA} TO {ROLE};
ALTER DEFAULT PRIVILEGES IN SCHEMA {SCHEMA} GRANT SELECT ON TABLES TO {ROLE};
"""

    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as tf:
        tf.write(sql)
        local_sql = tf.name

    try:
        r = run(["scp", "-i", SSH_KEY, local_sql, f"root@{CASEBIBLE_HOST}:/root/metabase_ro.sql"])
        assert r.returncode == 0, r.stderr

        r = run(["ssh", "-i", SSH_KEY, f"root@{CASEBIBLE_HOST}",
                 f"docker cp /root/metabase_ro.sql {CASEBIBLE_CONTAINER}:/tmp/metabase_ro.sql && "
                 f"docker exec {CASEBIBLE_CONTAINER} psql -v ON_ERROR_STOP=1 -U postgres -d {CASEBIBLE_DB} -f /tmp/metabase_ro.sql"])
        print("SQL apply rc:", r.returncode)
        print(r.stdout[-2000:])
        sql_ok = r.returncode == 0
        if not sql_ok:
            print(r.stderr[-2000:])

        # best-effort cleanup regardless of apply result — the file holds the
        # plaintext password and must not linger even if psql failed midway
        run(["ssh", "-i", SSH_KEY, f"root@{CASEBIBLE_HOST}",
             f"docker exec -u 0 {CASEBIBLE_CONTAINER} rm -f /tmp/metabase_ro.sql ; rm -f /root/metabase_ro.sql"])

        if not sql_ok:
            return 1
    finally:
        os.remove(local_sql)

    with tempfile.NamedTemporaryFile("w", suffix=".secret", delete=False, newline="\n") as tf:
        tf.write(pw + "\n")
        local_secret = tf.name

    try:
        r = run(["ssh", "-i", SSH_KEY, f"root@{APP_HOST}",
                 f"mkdir -p {SECRET_DIR} && chmod 700 {SECRET_DIR}"])
        assert r.returncode == 0, r.stderr

        r = run(["scp", "-i", SSH_KEY, local_secret, f"root@{APP_HOST}:{SECRET_PATH}"])
        assert r.returncode == 0, r.stderr

        r = run(["ssh", "-i", SSH_KEY, f"root@{APP_HOST}", f"chmod 600 {SECRET_PATH} && ls -la {SECRET_PATH}"])
        print(r.stdout)
    finally:
        os.remove(local_secret)

    print(f"Done. Role {ROLE!r} provisioned on {CASEBIBLE_DB}.{SCHEMA}; "
          f"password ({len(pw)} chars) written to {APP_HOST}:{SECRET_PATH} (mode 600). Not printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
