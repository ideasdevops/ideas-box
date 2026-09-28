"""
Ejecutor del panel: corre agentes con Claude Code y acciones de mantenimiento de
ideasbox en segundo plano, con la salida en vivo.

Tres filas independientes, cada una de a una ejecución por vez:

  · chat          conversaciones con un agente (lo que la persona está esperando)
  · tareas        tareas del tablero, a mano o programadas
  · mantenimiento revisar, actualizar, respaldar, conectar herramientas…

Así una tarea larga programada no deja esperando a quien está conversando.

Permisos (la regla que no se negocia): un agente del panel corre sin nadie que
apruebe en el momento, así que todo lo que pediría aprobación se deniega solo
(--permission-prompts none). Dos modos:

  · carpeta   puede crear y editar archivos dentro de la raíz de datos de la
              empresa (--permission-mode acceptEdits, con la raíz como carpeta de
              trabajo); leer y buscar, sí; comandos, publicar, enviar o desplegar,
              no: quedan anotados como «bloqueos» para que la persona los haga con
              su aprobación.
  · analizar  solo lee y propone (--permission-mode dontAsk: todo lo que pediría
              permiso, incluido escribir un archivo, se deniega): no toca nada.

Cada ejecución deja su salida en PANEL_DATA_DIR/runs/<id>.jsonl, una línea JSON
por evento: el panel la muestra en vivo y queda como historial.
"""
import json
import logging
import os
import queue
import shutil
import signal
import subprocess
import threading
import time
from pathlib import Path

from config import DATA_ROOT, MCP_REGISTRY, PANEL_DATA_DIR
from db import ajuste, db_session

logger = logging.getLogger("panel.runner")

RUNS_DIR = PANEL_DATA_DIR / "runs"
HOME = Path.home()
IDEASBOX = HOME / ".local" / "bin" / "ideasbox"


def claude_bin() -> str | None:
    for c in (shutil.which("claude"), HOME / ".local" / "bin" / "claude", HOME / ".claude" / "local" / "claude"):
        if c and Path(c).exists():
            return str(c)
    return None


def run_log(run_id: int) -> Path:
    return RUNS_DIR / f"{run_id}.jsonl"


# --- herramientas de solo lectura que los agentes del panel pueden usar solos -----

# Variantes de grupos de tools (catalog/tool-groups.tsv) que solo leen: se permiten
# sin aprobación. Todo lo demás (publicar, reiniciar, generar con créditos) no.
_GRUPOS_LECTURA = {
    "brave:all", "brave:research", "youtube:all", "codebase-memory:ro", "easypanel:ro",
    "ssh:ro", "chatwoot:ro", "instagram:ro", "facebook:ro", "facebook-ads:ro", "kling:ro",
}


def _tool_groups() -> dict[str, list[str]]:
    src = _stack_src()
    grupos: dict[str, list[str]] = {}
    f = src / "catalog" / "tool-groups.tsv" if src else None
    if not f or not f.exists():
        return grupos
    for line in f.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#") or "\t" not in line:
            continue
        g, tools = line.split("\t", 1)
        grupos[g.strip()] = [t.strip() for t in tools.split(",") if t.strip()]
    return grupos


def _stack_src() -> Path | None:
    from config import _PROFILE  # noqa: PLC0415 — mismo perfil que el resto del panel
    v = os.environ.get("STACK_SRC") or _PROFILE.get("STACK_SRC")
    return Path(v) if v else None


def herramientas_lectura() -> list[str]:
    """mcp__<servidor>__<tool> de los conectores instalados cuyo grupo es de lectura."""
    grupos = _tool_groups()
    permitidas = []
    if not MCP_REGISTRY.exists():
        return permitidas
    for raw in MCP_REGISTRY.read_text(encoding="utf-8").splitlines():
        cols = raw.split("\t")
        if len(cols) < 3 or cols[2] == "-":
            continue
        servidor, familia = cols[0], cols[2]
        for g, tools in grupos.items():
            if g.split(":")[0] == familia and g in _GRUPOS_LECTURA:
                permitidas += [f"mcp__{servidor}__{t}" for t in tools]
    return sorted(set(permitidas))


# --- traducción de la salida de Claude Code a eventos legibles --------------------

def _resumen_input(nombre: str, entrada: dict) -> str:
    for k in ("command", "file_path", "path", "pattern", "query", "url", "description", "prompt"):
        if entrada.get(k):
            v = str(entrada[k]).replace("\n", " ")
            return v[:220]
    return json.dumps(entrada, ensure_ascii=False)[:220]


def _texto_resultado(contenido) -> str:
    if isinstance(contenido, list):
        partes = [c.get("text", "") for c in contenido if isinstance(c, dict)]
        contenido = " ".join(partes)
    s = str(contenido or "").strip()
    return s[:600] + ("…" if len(s) > 600 else "")


class Runner:
    FILAS = ("chat", "tareas", "mantenimiento")

    def __init__(self):
        RUNS_DIR.mkdir(parents=True, exist_ok=True)
        self.colas = {f: queue.Queue() for f in self.FILAS}
        self.procesos: dict[int, subprocess.Popen] = {}
        self.lock = threading.Lock()
        self.al_terminar = []   # callbacks (run dict) — p. ej. actualizar la tarea
        for f in self.FILAS:
            threading.Thread(target=self._trabajador, args=(f,), daemon=True, name=f"runner-{f}").start()

    # --- encolar -----------------------------------------------------------------
    def _crear(self, **campos) -> int:
        cols = ", ".join(campos)
        with db_session() as conn:
            cur = conn.execute(f"INSERT INTO runs ({cols}) VALUES ({', '.join('?' * len(campos))})", tuple(campos.values()))
            return cur.lastrowid

    def encolar_agente(self, *, tipo: str, titulo: str, prompt: str, agente: str = "", modo: str = "carpeta",
                       tarea_id: int | None = None, hilo_id: int | None = None, origen: str = "manual",
                       resume: str | None = None) -> int:
        run_id = self._crear(tipo=tipo, titulo=titulo[:255], prompt=prompt, agente=agente, modo=modo,
                             tarea_id=tarea_id, hilo_id=hilo_id, origen=origen)
        self._evento(run_id, "sistema", "En la fila, esperando turno…")
        self.colas["chat" if tipo == "chat" else "tareas"].put(("agente", run_id, resume))
        return run_id

    def encolar_mantenimiento(self, *, titulo: str, accion: str, args: list[str], env_extra: dict | None = None,
                              origen: str = "manual") -> int:
        run_id = self._crear(tipo="mantenimiento", titulo=titulo, accion=accion, origen=origen, modo="carpeta")
        self._evento(run_id, "sistema", "En la fila, esperando turno…")
        self.colas["mantenimiento"].put(("mantenimiento", run_id, (args, env_extra or {})))
        return run_id

    def cancelar(self, run_id: int) -> bool:
        with db_session() as conn:
            row = conn.execute("SELECT estado FROM runs WHERE id = ?", (run_id,)).fetchone()
        if not row:
            return False
        if row["estado"] == "en_cola":
            self._cerrar(run_id, "cancelado", resultado="Cancelada antes de empezar.")
            return True
        p = self.procesos.get(run_id)
        if p and p.poll() is None:
            self._evento(run_id, "sistema", "Cancelando a pedido tuyo…")
            try:
                os.killpg(p.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                p.terminate()
            return True
        return False

    # --- eventos y cierre ---------------------------------------------------------
    def _evento(self, run_id: int, tipo: str, texto: str = "", **extra) -> None:
        ev = {"t": time.strftime("%H:%M:%S"), "tipo": tipo, "texto": texto, **extra}
        with self.lock, open(run_log(run_id), "a", encoding="utf-8") as f:
            f.write(json.dumps(ev, ensure_ascii=False) + "\n")

    def _estado(self, run_id: int) -> str:
        with db_session() as conn:
            row = conn.execute("SELECT estado FROM runs WHERE id = ?", (run_id,)).fetchone()
            return row["estado"] if row else "error"

    def _cerrar(self, run_id: int, estado: str, **campos) -> None:
        campos = {k: v for k, v in campos.items() if v is not None}
        sets = ", ".join(f"{k} = ?" for k in campos)
        with db_session() as conn:
            conn.execute(
                f"UPDATE runs SET estado = ?, fin = datetime('now','localtime'){', ' + sets if sets else ''} WHERE id = ?",
                (estado, *campos.values(), run_id),
            )
            run = dict(conn.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone())
        self._evento(run_id, "fin", estado=estado)
        for cb in self.al_terminar:
            try:
                cb(run)
            except Exception:  # noqa: BLE001 — un callback roto no puede tumbar al ejecutor
                logger.exception("callback al terminar")

    # --- trabajadores -------------------------------------------------------------
    def _trabajador(self, fila: str) -> None:
        while True:
            clase, run_id, extra = self.colas[fila].get()
            if self._estado(run_id) != "en_cola":   # cancelada mientras esperaba
                continue
            with db_session() as conn:
                conn.execute("UPDATE runs SET estado = 'corriendo', inicio = datetime('now','localtime') WHERE id = ?", (run_id,))
            try:
                if clase == "agente":
                    self._correr_agente(run_id, extra)
                else:
                    self._correr_mantenimiento(run_id, *extra)
            except Exception as e:  # noqa: BLE001
                logger.exception("ejecución %s", run_id)
                self._evento(run_id, "error", f"Error inesperado del panel: {e}")
                self._cerrar(run_id, "error", resultado=f"Error inesperado del panel: {e}")
            finally:
                self.procesos.pop(run_id, None)

    def _popen(self, run_id: int, cmd: list[str], env: dict, cwd: Path) -> subprocess.Popen:
        p = subprocess.Popen(
            cmd, cwd=str(cwd), env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, start_new_session=True, bufsize=1, text=True, encoding="utf-8", errors="replace",
        )
        self.procesos[run_id] = p
        return p

    def _correr_agente(self, run_id: int, resume: str | None) -> None:
        with db_session() as conn:
            run = dict(conn.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone())
        claude = claude_bin()
        if not claude:
            self._evento(run_id, "error", "No encuentro Claude Code en este equipo. Instalalo desde el menú de Ideas Box.")
            self._cerrar(run_id, "error", resultado="Falta Claude Code.")
            return

        max_turnos = ajuste("max_turnos", "40")
        cmd = [
            claude, "-p", run["prompt"], "--output-format", "stream-json", "--verbose",
            "--permission-mode", "acceptEdits" if run["modo"] == "carpeta" else "dontAsk",
            "--permission-prompts", "none", "--add-dir", str(DATA_ROOT), "--max-turns", max_turnos,
        ]
        if run["agente"]:
            cmd += ["--agent", run["agente"]]
        if resume:
            cmd += ["--resume", resume]
        permitidas = ["WebSearch", *herramientas_lectura()]
        cmd += ["--allowedTools", *permitidas]
        modelo = ajuste("modelo", "")
        if modelo:
            cmd += ["--model", modelo]

        modo_txt = "puede trabajar en la carpeta de la empresa" if run["modo"] == "carpeta" else "solo analiza, no toca archivos"
        self._evento(run_id, "sistema", f"Arrancando {run['agente'] or 'Claude'} ({modo_txt})")
        p = self._popen(run_id, cmd, dict(os.environ, NO_COLOR="1"), DATA_ROOT)

        final = None
        ultimo_texto = ""
        for linea in p.stdout:
            linea = linea.strip()
            if not linea:
                continue
            try:
                d = json.loads(linea)
            except json.JSONDecodeError:
                self._evento(run_id, "linea", linea[:500])
                continue
            t = d.get("type")
            if t == "system" and d.get("subtype") == "init":
                with db_session() as conn:
                    conn.execute("UPDATE runs SET session_id = ? WHERE id = ?", (d.get("session_id"), run_id))
                    if run["hilo_id"]:
                        conn.execute("UPDATE hilos SET session_id = ?, actualizado_en = datetime('now','localtime') WHERE id = ?",
                                     (d.get("session_id"), run["hilo_id"]))
            elif t == "assistant":
                for c in d.get("message", {}).get("content", []):
                    if c.get("type") == "text" and c.get("text", "").strip():
                        ultimo_texto = c["text"]
                        self._evento(run_id, "texto", c["text"])
                    elif c.get("type") == "tool_use":
                        self._evento(run_id, "herramienta", _resumen_input(c.get("name", ""), c.get("input") or {}),
                                     herramienta=c.get("name", ""))
            elif t == "user":
                contenido = d.get("message", {}).get("content", [])
                for c in contenido if isinstance(contenido, list) else []:
                    if c.get("type") == "tool_result":
                        self._evento(run_id, "resultado", _texto_resultado(c.get("content")), error=bool(c.get("is_error")))
            elif t == "result":
                final = d
        p.wait()

        if self._estado(run_id) == "cancelado" or p.returncode in (-signal.SIGTERM, 143):
            self._cerrar(run_id, "cancelado", resultado="Cancelada a pedido tuyo.")
            return
        if not final:
            self._evento(run_id, "error", f"Claude Code terminó sin resultado (código {p.returncode}).")
            self._cerrar(run_id, "error", resultado=f"Claude Code terminó sin resultado (código {p.returncode}).")
            return

        bloqueos = [
            f"{b.get('tool_name')}: {_resumen_input(b.get('tool_name', ''), b.get('tool_input') or {})}"
            for b in final.get("permission_denials") or []
        ]
        for b in bloqueos:
            self._evento(run_id, "bloqueo", b)
        # Si cortó por el límite de pasos, "result" puede venir vacío: vale lo último que dijo
        texto = final.get("result") or ultimo_texto
        if "Not logged in" in texto or "/login" in texto and final.get("is_error"):
            texto = ("Claude Code no tiene una sesión iniciada en este equipo. Abrí el ícono «Ideas Box», elegí "
                     "«Hablar con mis agentes» e iniciá sesión con tu cuenta de Claude una vez; después el panel ya "
                     "puede trabajar.")
            self._evento(run_id, "error", texto)
            self._cerrar(run_id, "error", resultado=texto)
            return
        if final.get("subtype") == "error_max_turns":
            texto = (texto + "\n\n" if texto else "") + f"(Se detuvo al llegar al límite de {max_turnos} pasos.)"
        estado = "error" if final.get("is_error") and final.get("subtype") != "error_max_turns" else "ok"
        self._evento(run_id, "final", texto, costo=final.get("total_cost_usd"), turnos=final.get("num_turns"))
        self._cerrar(run_id, estado, resultado=texto, bloqueos="\n".join(bloqueos) or None,
                     costo_usd=final.get("total_cost_usd"), turnos=final.get("num_turns"))

    def _correr_mantenimiento(self, run_id: int, args: list[str], env_extra: dict) -> None:
        if not IDEASBOX.exists():
            self._evento(run_id, "error", f"No encuentro el comando ideasbox en {IDEASBOX}.")
            self._cerrar(run_id, "error", resultado="Falta el comando ideasbox.")
            return
        # IB_GUI=1: las respuestas que manda el panel (IB_ANS_*) se usan en vez de preguntar;
        # lo que no venga, toma el valor por defecto (no hay terminal).
        env = dict(os.environ, NO_COLOR="1", IB_GUI="1", IB_DESDE_PANEL="1", **env_extra)
        self._evento(run_id, "sistema", "ideasbox " + " ".join(args))
        p = self._popen(run_id, ["bash", str(IDEASBOX), *args], env, HOME)
        ultimas = []
        for linea in p.stdout:
            linea = linea.rstrip()
            if not linea.strip() or linea.startswith("::ib::"):
                continue
            ultimas = (ultimas + [linea])[-12:]
            self._evento(run_id, "linea", linea)
        p.wait()
        if self._estado(run_id) == "cancelado":
            self._cerrar(run_id, "cancelado", resultado="Cancelada a pedido tuyo.")
            return
        ok = p.returncode == 0
        resumen = "\n".join(ultimas[-6:])
        self._evento(run_id, "final", "Terminó bien." if ok else f"Terminó con errores (código {p.returncode}).")
        self._cerrar(run_id, "ok" if ok else "error", resultado=resumen)


RUNNER: Runner | None = None


def runner() -> Runner:
    global RUNNER
    if RUNNER is None:
        RUNNER = Runner()
    return RUNNER


def leer_eventos(run_id: int, desde: int = 0) -> list[dict]:
    f = run_log(run_id)
    if not f.exists():
        return []
    with open(f, encoding="utf-8") as fh:
        lineas = fh.readlines()
    out = []
    for i, l in enumerate(lineas[desde:], start=desde):
        try:
            ev = json.loads(l)
        except json.JSONDecodeError:
            continue
        ev["n"] = i + 1
        out.append(ev)
    return out


