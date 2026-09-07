#!/usr/bin/env bash
# Coolify REST helper for cutover waves (list apps per server, trigger deploys, watch the queue).
# Byline: Claude Code · Fable 5.1 · 2026-09-07. Reads the token from ~/.secrets/coolify-ionos-api.env without sourcing it.
#   bash scripts/coolify_apps.sh list [server-name-substring]   # uuid | name | status | server | watch paths
#   bash scripts/coolify_apps.sh deploy <uuid>[,<uuid>...]      # POST /deploy?uuid=...  (redeploy from git)
#   bash scripts/coolify_apps.sh queue                          # in-progress / queued deployments (team-wide)
#   bash scripts/coolify_apps.sh servers                        # server uuids + names
set -euo pipefail
ENVF="${COOLIFY_ENV_FILE:-$HOME/.secrets/coolify-ionos-api.env}"
val() { grep -E "^\s*$1\s*=" "$ENVF" | head -1 | sed -E 's/^[^=]*=\s*//; s/^["'"'"']//; s/["'"'"']\s*$//'; }
TOKEN="$(val COOLIFY_API_TOKEN)"; BASE="$(val COOLIFY_API)"; [ -n "$BASE" ] || BASE="$(val COOLIFY_BASE_URL)"
BASE="${BASE%/}"; case "$BASE" in */api/v1) ;; *) BASE="$BASE/api/v1";; esac
[ -n "$TOKEN" ] || { echo "no COOLIFY_API_TOKEN in $ENVF"; exit 1; }
api() { curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" "$@"; }
case "${1:-}" in
app)
  api "$BASE/applications/$2" | python3 -c 'import json,sys; a=json.load(sys.stdin); [print(k,"=",a.get(k)) for k in ("name","uuid","status","git_repository","git_branch","base_directory","docker_compose_location","watch_paths","build_pack")]' ;;
services)
  api "$BASE/services" | python3 -c 'import json,sys; [print(s["uuid"], "|", s.get("name"), "|", s.get("status"), "|", (s.get("server") or {}).get("name") if isinstance(s.get("server"),dict) else s.get("server_id")) for s in json.load(sys.stdin)]' ;;
servers)
  api "$BASE/servers" | python3 -c 'import json,sys; [print(s["uuid"], "|", s.get("name"), "|", s.get("ip")) for s in json.load(sys.stdin)]' ;;
list)
  SERVERS_JSON="$(api "$BASE/servers")"
  api "$BASE/applications" | SERVERS_JSON="$SERVERS_JSON" python3 -c '
import json,sys,os
servers={s["uuid"]:s.get("name","?") for s in json.loads(os.environ["SERVERS_JSON"])}
apps=json.load(sys.stdin); want=(sys.argv[1] if len(sys.argv)>1 else "").lower()
for a in sorted(apps, key=lambda a:(a.get("destination",{}).get("server",{}).get("name","") if isinstance(a.get("destination"),dict) else "", a.get("name",""))):
    dest=a.get("destination") or {}; srv=(dest.get("server") or {}).get("name") or servers.get(a.get("server_uuid",""),"?")
    if want and want not in str(srv).lower(): continue
    print(a["uuid"], "|", a.get("name"), "|", a.get("status"), "|", srv, "|", (a.get("watch_paths") or "").replace("\n"," ")[:60])
' "${2:-}" ;;
deploy)
  [ -n "${2:-}" ] || { echo "uuid list required"; exit 2; }
  api -X POST "$BASE/deploy?uuid=$2&force=false" | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(x.get("message"), x.get("resource_uuid"), x.get("deployment_uuid")) for x in d.get("deployments", [d])]' ;;
queue)
  api "$BASE/deployments" | python3 -c 'import json,sys; d=json.load(sys.stdin); items=list(d.values()) if isinstance(d,dict) else d; print(len(items), "active"); [print(x.get("status"), "|", x.get("application_name") or x.get("application_id"), "|", x.get("deployment_uuid")) for x in items if isinstance(x,dict)]' ;;
*) echo "usage: $0 servers|services|list [server]|app <uuid>|deploy <uuids>|queue"; exit 2;;
esac
