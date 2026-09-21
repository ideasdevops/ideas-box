#!/usr/bin/env bash
# settings.json de Claude Code: permisos, zonas denegadas y hook de arranque.
# Se hace merge, nunca se pisa la configuración que el usuario ya tenía.

settings_apply() {
  step "8/8 · Configuración de Claude Code"
  local settings="$CLAUDE_CONFIG_DIR/settings.json"

  DATA_ROOT="$DATA_ROOT" STACK_CONFIG_DIR="$STACK_CONFIG_DIR" HOOK="$CLAUDE_CONFIG_DIR/hooks/ideasbox-session-start" \
  python3 - <<'PY' | json_merge "$settings"
import json, os

data_root = os.environ["DATA_ROOT"]
cfg = os.environ["STACK_CONFIG_DIR"]
hook = os.environ["HOOK"]

allow = [
    # lectura y navegación: ruido puro si cada una pide permiso
    "Bash(ls:*)", "Bash(cat:*)", "Bash(head:*)", "Bash(tail:*)", "Bash(wc:*)",
    "Bash(grep:*)", "Bash(rg:*)", "Bash(find:*)", "Bash(file:*)", "Bash(stat:*)",
    "Bash(df:*)", "Bash(du:*)", "Bash(lsblk:*)", "Bash(mount)", "Bash(date)",
    "Bash(git status:*)", "Bash(git log:*)", "Bash(git diff:*)", "Bash(git show:*)",
    "Bash(git branch:*)", "Bash(git remote:*)",
    "Bash(docker ps:*)", "Bash(docker logs:*)", "Bash(docker stats:*)",
    "Bash(ffprobe:*)", "Bash(jq:*)",
]

deny = [
    # secretos: ni leer ni copiar, aunque el agente crea que los necesita
    f"Read({cfg}/secrets/**)",
    "Read(//home/*/.ssh/**)",
    "Read(//**/.env)",
    "Read(//**/.env.*)",
    "Read(//**/id_rsa)",
    "Read(//**/id_ed25519)",
    f"Bash(cat {cfg}/secrets/*)",
]

print(json.dumps({
    "permissions": {
        "allow": allow,
        "deny": deny,
        "additionalDirectories": [data_root],
    },
    "hooks": {
        "SessionStart": [
            {"hooks": [{"type": "command", "command": hook}]}
        ]
    },
}, ensure_ascii=False))
PY

  ok "settings.json actualizado (merge, sin perder lo tuyo)"
}
