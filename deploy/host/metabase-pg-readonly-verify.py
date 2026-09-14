#!/usr/bin/env python3
"""Read-only verification companion to metabase-pg-readonly-setup.py:
confirms the staging temp files were cleaned up and the metabase_ro role
grants landed as expected. No writes, no secrets printed.

Byline: Claude Code · Sonnet 5 · 2026-09-14
"""
import os
import subprocess

SSH_KEY = os.path.expanduser("~/.ssh/ovh")
CASEBIBLE_HOST = "100.91.190.107"
CASEBIBLE_CONTAINER = "fgz1n7useplhk0t91uk7k1aw"


def run(cmd):
    env = dict(os.environ)
    env["MSYS_NO_PATHCONV"] = "1"
    return subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=30)


def main():
    r = run(["ssh", "-i", SSH_KEY, f"root@{CASEBIBLE_HOST}",
             "test -f /root/metabase_ro.sql && echo 'HOST FILE STILL PRESENT' || echo 'host file gone'"])
    print(r.stdout.strip(), r.stderr.strip())

    r = run(["ssh", "-i", SSH_KEY, f"root@{CASEBIBLE_HOST}",
             f"docker exec {CASEBIBLE_CONTAINER} test -f /tmp/metabase_ro.sql && echo 'CONTAINER FILE STILL PRESENT' || echo 'container file gone'"])
    print(r.stdout.strip(), r.stderr.strip())

    r = run(["ssh", "-i", SSH_KEY, f"root@{CASEBIBLE_HOST}",
             f"docker exec {CASEBIBLE_CONTAINER} psql -U postgres -d casebible -c "
             "\"SELECT grantee, table_name, privilege_type FROM information_schema.role_table_grants "
             "WHERE grantee='metabase_ro' ORDER BY table_name, privilege_type;\""])
    print(r.stdout)
    if r.returncode != 0:
        print(r.stderr)


if __name__ == "__main__":
    main()
