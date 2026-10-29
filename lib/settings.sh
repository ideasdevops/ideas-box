#!/usr/bin/env bash
# settings.json de Claude Code: permisos, zonas denegadas, hooks y uso del plan.
# Se hace merge, nunca se pisa la configuración que el usuario ya tenía.

settings_apply() {
  step "8/8 · Configuración de Claude Code"
  local settings="$CLAUDE_CONFIG_DIR/settings.json"

  # Si ya había una barra de estado propia, se encadena: sigue apareciendo arriba de la del uso.
  local fb="$STACK_SRC/bin/ideasbox-fallback" prev
  prev="$(SETTINGS="$settings" FB="$fb" python3 -c '
import json, os
try:
    c = (json.load(open(os.environ["SETTINGS"])).get("statusLine") or {}).get("command", "")
except Exception:
    c = ""
print("" if "ideasbox-fallback" in c else c)')"
  [ -n "$prev" ] && fallback_conf_set PREV_STATUSLINE "$prev"

  DATA_ROOT="$DATA_ROOT" STACK_CONFIG_DIR="$STACK_CONFIG_DIR" USER_HOME="$HOME" \
  SETTINGS="$settings" FB="$fb" \
  HOOK="$CLAUDE_CONFIG_DIR/hooks/ideasbox-session-start" \
  python3 - <<'PY' | json_merge "$settings"
import json, os, shlex

data_root = os.environ["DATA_ROOT"]
cfg = os.environ["STACK_CONFIG_DIR"]
home = os.environ["USER_HOME"]
hook = os.environ["HOOK"]
fb = shlex.quote(os.environ["FB"])  # la carpeta del stack puede tener espacios
try:
    actual = json.load(open(os.environ["SETTINGS"]))
except Exception:
    actual = {}

allow = [
    # lectura y navegación: ruido puro si cada una pide permiso
    "Bash(ls:*)", "Bash(cat:*)", "Bash(head:*)", "Bash(tail:*)", "Bash(wc:*)",
    "Bash(grep:*)", "Bash(rg:*)", "Bash(find:*)", "Bash(file:*)", "Bash(stat:*)",
    "Bash(df:*)", "Bash(du:*)", "Bash(lsblk:*)", "Bash(diskutil list)", "Bash(mount)", "Bash(date)",
    "Bash(git status:*)", "Bash(git log:*)", "Bash(git diff:*)", "Bash(git show:*)",
    "Bash(git branch:*)", "Bash(git remote:*)",
    "Bash(docker ps:*)", "Bash(docker logs:*)", "Bash(docker stats:*)",
    "Bash(ffprobe:*)", "Bash(jq:*)",
]

deny = [
    # secretos: ni leer ni copiar, aunque el agente crea que los necesita
    f"Read({cfg}/secrets/**)",
    f"Read({home}/.ssh/**)",
    "Read(//**/.env)",
    "Read(//**/.env.*)",
    "Read(//**/id_rsa)",
    "Read(//**/id_ed25519)",
    f"Bash(cat {cfg}/secrets/*)",
]

patch = {
    "permissions": {
        "allow": allow,
        "deny": deny,
        "additionalDirectories": [data_root],
    },
    "hooks": {
        "SessionStart": [
            {"hooks": [{"type": "command", "command": hook}]},
            # al volver a una sesión cortada por límite: avisar qué hizo el motor local
            {"matcher": "resume", "hooks": [{"type": "command", "command": f"{fb} resume", "timeout": 5}]},
        ],
        # con uso alto del plan, cada mensaje le pide a Claude que ahorre
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": f"{fb} guard", "timeout": 5}]}],
        # se cortó por límite: traspaso escrito, aviso y (si está) motor local
        "StopFailure": [{"matcher": "rate_limit|billing_error",
                         "hooks": [{"type": "command", "command": f"{fb} handoff", "timeout": 20}]}],
    },
    "statusLine": {"type": "command", "command": f"{fb} statusline"},
}
# Orquestador: Sonnet decide y deriva a Opus solo lo difícil (ver CLAUDE.md). Si el usuario
# ya eligió un modelo, se respeta.
if "model" not in actual:
    patch["model"] = "sonnet"
print(json.dumps(patch, ensure_ascii=False))
PY

  ok "settings.json actualizado (merge, sin perder lo tuyo)"
}
