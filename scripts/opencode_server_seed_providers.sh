#!/usr/bin/env bash
# Seed the headless opencode-server (ovh-files) with provider auth so delegated work runs on free/cheap
# providers, spread out (owner 2026-09-07 21:23-21:25): NVIDIA NIM + the desktop's existing OpenCode auth
# (ollama-cloud etc.) + OpenRouter/Groq/Cerebras keys when present in ~/.secrets. Writes
# /home/opencode/.local/share/opencode/auth.json (0600, uid 1000) and a minimal opencode.json with a NIM
# default model. Keys read by tolerant regex, sent over ssh stdin, never printed. Re-runnable.
# Byline: Claude Code · Fable 5.1 · 2026-09-07
set -euo pipefail
HOST="${DEVBOX_HOST:-root@100.91.190.107}"; KEY="${DEVBOX_SSH_KEY:-$HOME/.ssh/ovh}"
OC=/data/probata/volumes/opencode/home
python3 - <<'PY' > /tmp/oc_auth.json
import json,os,re,glob
env={}
for f in sorted(glob.glob(os.path.expanduser('~/.secrets/*.env'))):
    for line in open(f,encoding='utf-8',errors='replace'):
        m=re.match(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$',line)
        if m and m.group(1) not in env:
            v=re.sub(r'\s+#.*$','',m.group(2)).strip().strip('"').strip("'")   # drop inline "# comment" tails (the GEMINI line has one)
            env[m.group(1)]=v
auth={}
try: auth=json.load(open(os.path.expanduser('~/.local/share/opencode/auth.json')))
except Exception: pass
for prov,var in [("nvidia","NVIDIA_API_KEY"),("openrouter","OPENROUTER_API_KEY"),("groq","GROQ_API_KEY"),("cerebras","CEREBRAS_API_KEY"),("mistral","MISTRAL_API_KEY"),("google","GEMINI_API_KEY")]:
    if env.get(var): auth[prov]={"type":"api","key":env[var]}   # always refresh from ~/.secrets (owner 2026-09-08: update the gemini key)
print(json.dumps(auth))
import sys; sys.stderr.write("providers: "+", ".join(sorted(auth))+"\n")
PY
cat > /tmp/oc_config.json <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "nvidia/nvidia/nemotron-3-super-120b-a12b",
  "small_model": "nvidia/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
  "autoupdate": false
}
JSON
ssh -i "$KEY" -o BatchMode=yes "$HOST" "install -d -o 1000 -g 1000 -m 700 $OC/.local/share/opencode $OC/.config/opencode && cat > $OC/.local/share/opencode/auth.json && chown 1000:1000 $OC/.local/share/opencode/auth.json && chmod 600 $OC/.local/share/opencode/auth.json && echo auth.json seeded" < /tmp/oc_auth.json
scp -q -i "$KEY" /tmp/oc_config.json "$HOST:$OC/.config/opencode/opencode.json" && ssh -i "$KEY" -o BatchMode=yes "$HOST" "chown 1000:1000 $OC/.config/opencode/opencode.json && echo opencode.json seeded"
rm -f /tmp/oc_auth.json /tmp/oc_config.json
echo "restart the opencode-server app in Coolify so it reloads auth; then: curl -u opencode:<pw> http://100.91.190.107:4096/config/providers"
