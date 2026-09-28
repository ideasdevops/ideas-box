#!/usr/bin/env python3
"""Servidor del asistente gráfico de instalación de Ideas Box.

Lo arranca `install.sh --gui` (lib/gui.sh). Sirve la interfaz precompilada de
installer/web/dist y una API local para:

  · mostrar lo que el asistente necesita saber del equipo (sistema, perfil previo,
    instalación a medias, catálogo de habilidades y conectores, dónde guardar datos);
  · correr `install.sh --gui-run` con las respuestas de los formularios en un archivo
    (600, se borra al cerrar) y transmitir su salida en vivo (Server-Sent Events);
  · reenviar al instalador lo que se responde en los modales (FIFO en el descriptor 3).

Solo biblioteca estándar y compatible con Python 3.8: en Mac corre con el Python que
traen las herramientas de Apple, antes de que se instale nada más.

Seguridad: escucha en 127.0.0.1 (en WSL, 0.0.0.0 para que llegue el navegador de
Windows; la red de WSL no sale del equipo), exige un token aleatorio en cada llamada
a la API y rechaza cabeceras Host ajenas (DNS rebinding).
"""

import argparse
import json
import os
import platform
import re
import secrets
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
STEP_LABELS = {
    "deps": "Programas del sistema",
    "perfil": "Datos de tu empresa",
    "datos": "Carpeta de datos",
    "packs": "Habilidades",
    "mcp": "Conectores",
    "canonico": "Agentes y memoria",
    "settings": "Configuración de Claude Code",
    "cli": "Accesos directos",
    "panel": "Panel de tareas",
}
STEP_ORDER = list(STEP_LABELS)
IDLE_BEFORE_START = 3 * 3600   # sin nadie mirando y sin arrancar: se cierra solo
IDLE_AFTER_END = 20 * 60       # terminada la instalación y sin navegador conectado


def home():
    return os.path.expanduser("~")


def config_dir():
    return os.environ.get("STACK_CONFIG_DIR") or os.path.join(home(), ".config", "ideasbox")


def is_wsl():
    if platform.system() != "Linux":
        return False
    if os.environ.get("WSL_DISTRO_NAME"):
        return True
    try:
        with open("/proc/sys/kernel/osrelease") as f:
            return "microsoft" in f.read().lower()
    except OSError:
        return False


def os_kind():
    if platform.system() == "Darwin":
        return "mac"
    return "wsl" if is_wsl() else "linux"


def os_pretty():
    if platform.system() == "Darwin":
        try:
            v = subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip()
            return "macOS " + v
        except OSError:
            return "macOS"
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    name = line.split("=", 1)[1].strip().strip('"')
                    return name + (" (WSL)" if is_wsl() else "")
    except OSError:
        pass
    return "Linux"


def timezone_name():
    try:
        link = os.path.realpath("/etc/localtime")
        if "zoneinfo/" in link:
            return link.split("zoneinfo/", 1)[1]
    except OSError:
        pass
    try:
        with open("/etc/timezone") as f:
            return f.read().strip()
    except OSError:
        return "UTC"


def parse_shell_assignments(path):
    """KEY="valor" de los archivos del stack (.mcp, empresa.conf). Sin expandir variables."""
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return out
    for line in lines:
        m = re.match(r"^([A-Z_][A-Z0-9_]*)=(.*)$", line.strip())
        if not m:
            continue
        try:
            parts = shlex.split(m.group(2), comments=True)
            out[m.group(1)] = " ".join(parts)
        except ValueError:
            out[m.group(1)] = m.group(2).strip("\"'")
    return out


class Installer:
    def __init__(self, src, extra_args):
        self.src = src
        self.extra_args = extra_args
        self.lock = threading.Condition()
        self.events = []
        self.seq = 0
        self.status = "idle"        # idle · running · done · failed
        self.proc = None
        self.answers = None
        self.answers_path = None
        self.data_root = ""
        self.tmp = tempfile.mkdtemp(prefix="ideasbox-gui-")
        os.chmod(self.tmp, 0o700)
        self.fifo = os.path.join(self.tmp, "respuestas")
        os.mkfifo(self.fifo, 0o600)
        # Un lector que nunca lee mantiene abierto el FIFO, así abrir el escritor no se
        # bloquea y bash (que abre su lado al arrancar) tampoco.
        self._fifo_keep = os.open(self.fifo, os.O_RDONLY | os.O_NONBLOCK)
        self._fifo_w = os.open(self.fifo, os.O_WRONLY)
        self.clients = 0
        self.last_seen = time.time()
        self.pending_ask = None

    # --- eventos ---------------------------------------------------------------
    def emit(self, kind, **data):
        with self.lock:
            self.seq += 1
            ev = dict(seq=self.seq, kind=kind, t=time.time(), **data)
            self.events.append(ev)
            if len(self.events) > 20000:
                self.events = self.events[-15000:]
            self.lock.notify_all()
        return ev

    def events_since(self, since, timeout):
        with self.lock:
            if not any(e["seq"] > since for e in self.events):
                self.lock.wait(timeout)
            return [e for e in self.events if e["seq"] > since]

    # --- catálogo e información del equipo --------------------------------------
    def installed_mcps(self):
        ids = set()
        try:
            with open(os.path.join(config_dir(), "mcp-installed.tsv"), encoding="utf-8") as f:
                for line in f:
                    cols = line.rstrip("\n").split("\t")
                    if len(cols) >= 2:
                        ids.add(cols[1])
        except OSError:
            pass
        return ids

    def catalog(self):
        installed = self.installed_mcps()
        mcps = []
        cat = os.path.join(self.src, "catalog", "mcp")
        for name in sorted(os.listdir(cat)):
            if not name.endswith(".mcp"):
                continue
            d = parse_shell_assignments(os.path.join(cat, name))
            keys = d.get("ENV_KEYS", "").split()
            secret = set(d.get("ENV_SECRET", "").split())
            mcps.append({
                "id": d.get("ID", name[:-4]),
                "title": d.get("TITLE", ""),
                "desc": d.get("DESC", ""),
                "tier": d.get("TIER", "negocio"),
                "recommended": d.get("RECOMMENDED") == "1",
                "kind": d.get("KIND", ""),
                "multi": d.get("MULTI") == "1",
                "instancePrompt": d.get("INSTANCE_PROMPT", ""),
                "fields": [{"key": k, "prompt": d.get("ENV_PROMPT_" + k, k), "secret": k in secret} for k in keys],
                "login": bool(d.get("LOGIN_CMD")),
                "suggest": d.get("SUGGEST", ""),
                "notes": d.get("NOTES", ""),
                "requiresHost": d.get("REQUIRES_HOST", ""),
                "installed": d.get("ID", name[:-4]) in installed,
            })
        packs = []
        try:
            with open(os.path.join(self.src, "catalog", "skill-packs.tsv"), encoding="utf-8") as f:
                for line in f:
                    if not line.strip() or line.startswith("#"):
                        continue
                    cols = line.rstrip("\n").split("\t")
                    if len(cols) < 6 or cols[1] == "conector":
                        continue
                    packs.append({"id": cols[0], "tier": cols[1], "domain": cols[2], "desc": cols[5]})
        except OSError:
            pass
        return {"mcps": mcps, "packs": packs}

    def info(self):
        prof = parse_shell_assignments(os.path.join(config_dir(), "empresa.conf"))
        resume = []
        try:
            with open(os.path.join(config_dir(), "install.state")) as f:
                resume = [s.strip() for s in f if s.strip()]
        except OSError:
            pass
        panel = os.path.join(home(), ".local", "share", "ideasbox", "panel", "backend", "venv", "bin", "uvicorn")
        return {
            "os": os_kind(),
            "osPretty": os_pretty(),
            "arch": platform.machine(),
            "user": os.environ.get("USER", ""),
            "home": home(),
            "timezone": timezone_name(),
            "version": open(os.path.join(self.src, "VERSION")).read().strip() if os.path.exists(os.path.join(self.src, "VERSION")) else "",
            "profile": {k: prof.get(k, "") for k in (
                "EMPRESA_NOMBRE", "EMPRESA_SLUG", "EMPRESA_RUBRO", "EMPRESA_SITIO",
                "EMPRESA_RESPONSABLE", "EMPRESA_IDIOMA", "EMPRESA_TZ", "DATA_ROOT")},
            "resume": [{"id": s, "label": STEP_LABELS.get(s, s)} for s in resume],
            "panelInstalled": os.path.exists(panel),
            "steps": [{"id": s, "label": STEP_LABELS[s]} for s in STEP_ORDER],
            "skipDeps": "--skip-deps" in self.extra_args,
            "dryRun": "--dry-run" in self.extra_args,
            "status": self.status,
            **self.catalog(),
        }

    def dataroots(self, slug):
        r = subprocess.run(
            ["bash", os.path.join(self.src, "install.sh"), "--gui-probe", slug or "mi-empresa"],
            capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL,
        )
        out = []
        for line in r.stdout.splitlines():
            cols = line.split("\t")
            if len(cols) >= 5:
                out.append({"path": cols[0], "label": cols[1], "free": cols[2],
                            "recommended": cols[3] == "1", "exists": cols[4] == "1"})
        return out

    # --- instalación ---------------------------------------------------------------
    def _answers_file(self, a):
        """Traduce los formularios a IB_ANS_<clave> (ver confirm/ask en lib/common.sh)."""
        def key(k):
            return "IB_ANS_" + re.sub(r"[^A-Za-z0-9_]", "_", k)

        yes = lambda b: "s" if b else "n"  # noqa: E731
        cat = self.catalog()
        fields = {m["id"]: [f["key"] for f in m["fields"]] for m in cat["mcps"]}
        vals = {}
        if a.get("resume"):
            vals["resume"] = "s"
        else:
            vals["resume"] = "n"
            emp = a.get("empresa", {})
            vals["reuse_profile"] = "n"
            for f in ("NOMBRE", "SLUG", "RUBRO", "SITIO", "RESPONSABLE", "IDIOMA", "TZ"):
                vals["EMPRESA_" + f] = (emp.get(f.lower()) or "").strip()
            # Todo el catálogo queda respondido: lo que no vino en el formulario es «no», así
            # el instalador nunca se queda esperando una respuesta que nadie va a dar
            for pk in cat["packs"]:
                vals["pack_" + pk["id"]] = "n"
            for mc in cat["mcps"]:
                vals["mcp_" + mc["id"]] = "n"
                vals["mcp_more_" + mc["id"]] = "n"
                # El núcleo se instala siempre: sus claves (Brave) también quedan respondidas
                if mc["tier"] == "core":
                    vals["reuse_" + mc["id"]] = "s"
                    for f in mc["fields"]:
                        vals["cred_%s_%s" % (mc["id"], f["key"])] = ""
            for p in a.get("packs", []):
                vals["pack_" + p["id"]] = yes(p.get("on"))
            for m in a.get("mcps", []):
                mid = m["id"]
                vals["mcp_" + mid] = yes(m.get("on"))
                vals["mcp_more_" + mid] = "n"
                if not m.get("on"):
                    continue
                if m.get("label"):
                    vals["label_" + mid] = m["label"]
                given = {k: v for k, v in (m.get("creds") or {}).items() if v}
                # Sin datos nuevos, se reusan los que ya haya; con datos nuevos, se reemplazan
                vals["reuse_" + mid] = "n" if given else "s"
                # Todos los campos del conector, también los vacíos: si falta uno, el
                # instalador lo pregunta con un modal a mitad de la instalación
                for k in fields.get(mid, []):
                    vals["cred_%s_%s" % (mid, k)] = given.get(k, "")
                vals["login_" + mid] = yes(m.get("login", True))
            ex = a.get("extras", {})
            vals["media"] = yes(ex.get("media", True))
            vals["docker"] = yes(ex.get("docker", False))
            vals["panel"] = yes(ex.get("panel", True))
            vals["brew"] = "s"
            for s in ("shortcut_menu", "shortcut_data", "shortcut_panel"):
                vals[s] = yes(ex.get("shortcuts", True))
        lines = ["# Respuestas del asistente — se borra al cerrarlo. No compartir."]
        for k, v in vals.items():
            lines.append("%s=%s" % (key(k), shlex.quote(str(v).replace("\n", " "))))
        path = os.path.join(self.tmp, "respuestas.sh")
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        return path

    def start(self, answers):
        with self.lock:
            if self.status == "running":
                raise ValueError("La instalación ya está en marcha.")
            self.status = "running"
        self.answers = answers
        self.answers_path = self._answers_file(answers)
        cmd = ["bash", os.path.join(self.src, "install.sh"), "--gui-run", "--answers", self.answers_path]
        root = (answers.get("dataRoot") or "").strip()
        if root and not answers.get("resume"):
            cmd += ["--data-root", root]
            self.data_root = root
        cmd += self.extra_args
        env = dict(os.environ, IB_GUI="1", IB_GUI_FIFO=self.fifo, NO_COLOR="1", TERM="dumb")
        self.emit("started")
        self.proc = subprocess.Popen(
            cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env=env, cwd=home(), bufsize=0,
        )
        threading.Thread(target=self._pump, daemon=True).start()

    def retry(self):
        if self.status == "running" or not self.answers:
            raise ValueError("No hay una instalación para reintentar.")
        a = dict(self.answers)
        a["resume"] = True
        self.start(a)

    def _pump(self):
        term = sys.stdout
        for raw in iter(self.proc.stdout.readline, b""):
            line = ANSI.sub("", raw.decode("utf-8", "replace")).rstrip("\r\n")
            if line.startswith("::ib::"):
                parts = line[6:].split("\t")
                kind, f = parts[0], parts[1:]
                if kind == "step" and len(f) >= 2:
                    self.emit("step", id=f[0], state=f[1], label=STEP_LABELS.get(f[0], f[0]))
                    if f[1] == "start":
                        print("→ %s…" % STEP_LABELS.get(f[0], f[0]), file=term, flush=True)
                elif kind == "ask" and len(f) >= 3:
                    self.pending_ask = self.emit("ask", type=f[0], default=f[1], question="\t".join(f[2:]))
                    print("? El asistente te está preguntando algo en el navegador.", file=term, flush=True)
                elif kind == "failed":
                    self.emit("failed", step=f[0] if f else "", label=STEP_LABELS.get(f[0], f[0]) if f else "")
                elif kind == "done":
                    self.emit("summary", empresa=f[0] if f else "", dataRoot=f[1] if len(f) > 1 else "")
                elif kind == "title":
                    self.emit("title", text="\t".join(f))
                continue
            self.emit("log", text=line)
        rc = self.proc.wait()
        with self.lock:
            self.status = "done" if rc == 0 else "failed"
            self.pending_ask = None
        self.emit("exit", code=rc)
        if rc == 0:
            print("✓ Instalación terminada. Podés cerrar el asistente desde el navegador.", file=term, flush=True)
            self._forget_answers()
        else:
            print("✗ La instalación se cortó. El asistente muestra qué pasó y permite reintentar.", file=term, flush=True)

    def answer(self, value):
        if not self.pending_ask:
            raise ValueError("No hay ninguna pregunta pendiente.")
        ask = self.pending_ask
        self.pending_ask = None
        os.write(self._fifo_w, (str(value).replace("\n", " ") + "\n").encode("utf-8"))
        shown = "••••" if ask.get("type") == "secret" and value else (value or "(valor por defecto)")
        self.emit("answered", seq_ask=ask["seq"], text=shown)

    def cancel(self):
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGINT)

    def _forget_answers(self):
        if self.answers_path and os.path.exists(self.answers_path):
            os.remove(self.answers_path)
        self.answers_path = None

    def cleanup(self):
        self.cancel()
        self._forget_answers()
        for fd in (self._fifo_w, self._fifo_keep):
            try:
                os.close(fd)
            except OSError:
                pass
        shutil.rmtree(self.tmp, ignore_errors=True)


def open_browser(url):
    kind = os_kind()
    cmds = {
        "mac": [["open", url]],
        "wsl": [["wslview", url], ["explorer.exe", url], ["cmd.exe", "/c", "start", "", url]],
        "linux": [["xdg-open", url], ["gio", "open", url]],
    }[kind]
    for c in cmds:
        if shutil.which(c[0]):
            try:
                subprocess.Popen(c, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return True
            except OSError:
                continue
    return False


def make_handler(inst, token, dist, allowed_hosts, server_ref):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):   # la terminal muestra el progreso, no cada pedido
            pass

        # --- utilidades ---
        def _host_ok(self):
            return (self.headers.get("Host") or "") in allowed_hosts

        def _token_ok(self, qs):
            given = self.headers.get("X-IB-Token") or (qs.get("t") or [""])[0]
            return secrets.compare_digest(given, token)

        def _json(self, code, data):
            body = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _body(self):
            n = int(self.headers.get("Content-Length") or 0)
            if n > 1_000_000:
                raise ValueError("Pedido demasiado grande")
            return json.loads(self.rfile.read(n) or b"{}")

        # --- GET ---
        def do_GET(self):
            if not self._host_ok():
                return self._json(403, {"error": "host"})
            u = urlparse(self.path)
            qs = parse_qs(u.query)
            inst.last_seen = time.time()
            if u.path.startswith("/api/"):
                if not self._token_ok(qs):
                    return self._json(401, {"error": "token"})
                if u.path == "/api/info":
                    return self._json(200, inst.info())
                if u.path == "/api/dataroots":
                    return self._json(200, {"options": inst.dataroots((qs.get("slug") or [""])[0])})
                if u.path == "/api/events":
                    return self._sse(int((qs.get("since") or ["0"])[0]))
                return self._json(404, {"error": "no existe"})
            return self._static(u.path)

        def _static(self, path):
            rel = path.lstrip("/") or "index.html"
            full = os.path.realpath(os.path.join(dist, rel))
            if not full.startswith(os.path.realpath(dist)) or not os.path.isfile(full):
                full = os.path.join(dist, "index.html")   # SPA
            ctype = {
                ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png",
                ".ico": "image/x-icon", ".woff2": "font/woff2", ".json": "application/json",
            }.get(os.path.splitext(full)[1], "application/octet-stream")
            with open(full, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(body)

        def _sse(self, since):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            inst.clients += 1
            try:
                while True:
                    evs = inst.events_since(since, 15)
                    if evs:
                        for e in evs:
                            self.wfile.write(("data: %s\n\n" % json.dumps(e, ensure_ascii=False)).encode("utf-8"))
                        since = evs[-1]["seq"]
                    else:
                        self.wfile.write(b": sigo aca\n\n")
                    self.wfile.flush()
                    inst.last_seen = time.time()
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass
            finally:
                inst.clients -= 1
                self.close_connection = True

        # --- POST ---
        def do_POST(self):
            if not self._host_ok():
                return self._json(403, {"error": "host"})
            u = urlparse(self.path)
            if not self._token_ok({}):   # POST solo con cabecera: un sitio ajeno no puede ponerla
                return self._json(401, {"error": "token"})
            inst.last_seen = time.time()
            try:
                body = self._body()
                if u.path == "/api/start":
                    inst.start(body)
                elif u.path == "/api/answer":
                    inst.answer(body.get("value", ""))
                elif u.path == "/api/retry":
                    inst.retry()
                elif u.path == "/api/cancel":
                    inst.cancel()
                elif u.path == "/api/open":
                    what = body.get("what")
                    cli = os.path.join(home(), ".local", "bin", "ideasbox")
                    args = {"panel": ["panel", "open"], "folder": ["carpeta"]}.get(what)
                    if not args or not os.path.exists(cli):
                        return self._json(400, {"error": "No disponible"})
                    subprocess.Popen(["bash", cli] + args, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
                elif u.path == "/api/shutdown":
                    self._json(200, {"ok": True})
                    threading.Thread(target=server_ref[0].shutdown, daemon=True).start()
                    return None
                else:
                    return self._json(404, {"error": "no existe"})
                return self._json(200, {"ok": True})
            except ValueError as e:
                return self._json(409, {"error": str(e)})

    return Handler


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--port", type=int, default=8421)
    ap.add_argument("--no-browser", action="store_true")
    ap.add_argument("--skip-deps", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    dist = os.path.join(args.src, "installer", "web", "dist")
    if not os.path.isfile(os.path.join(dist, "index.html")):
        print("✗ Falta la interfaz del asistente (installer/web/dist).", file=sys.stderr)
        sys.exit(2)
    extra = (["--skip-deps"] if args.skip_deps else []) + (["--dry-run"] if args.dry_run else [])
    inst = Installer(args.src, extra)
    token = secrets.token_urlsafe(24)
    bind = "0.0.0.0" if is_wsl() else "127.0.0.1"

    server_ref = [None]
    httpd = None
    for port in [args.port] + list(range(args.port + 1, args.port + 30)) + [0]:
        try:
            allowed = set()
            handler = make_handler(inst, token, dist, allowed, server_ref)
            httpd = ThreadingHTTPServer((bind, port), handler)
            real = httpd.server_address[1]
            allowed.update({"127.0.0.1:%d" % real, "localhost:%d" % real})
            break
        except OSError:
            continue
    if httpd is None:
        print("✗ No pude abrir un puerto local para el asistente.", file=sys.stderr)
        sys.exit(2)
    httpd.daemon_threads = True
    server_ref[0] = httpd
    host = "localhost" if is_wsl() else "127.0.0.1"
    url = "http://%s:%d/?t=%s" % (host, httpd.server_address[1], token)

    def stop(*_):
        threading.Thread(target=httpd.shutdown, daemon=True).start()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)

    def watchdog():
        while True:
            time.sleep(30)
            idle = time.time() - inst.last_seen
            if inst.status == "running" or inst.clients > 0:
                continue
            limit = IDLE_AFTER_END if inst.status in ("done", "failed") else IDLE_BEFORE_START
            if idle > limit:
                print("→ El asistente se cerró por inactividad. Para volver a abrirlo: bash install.sh --gui", flush=True)
                stop()
                return
    threading.Thread(target=watchdog, daemon=True).start()

    print("", flush=True)
    print("  Ideas Box — asistente de instalación", flush=True)
    print("", flush=True)
    opened = False if (args.no_browser or os.environ.get("IB_GUI_NO_BROWSER")) else open_browser(url)
    print("  %s en tu navegador." % ("Se abrió" if opened else "Abrilo"), flush=True)
    print("  Si no aparece, copiá esta dirección en el navegador:", flush=True)
    print("    %s" % url, flush=True)
    print("", flush=True)
    print("  No cierres esta ventana mientras dure la instalación.", flush=True)
    print("", flush=True)
    try:
        httpd.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        inst.cleanup()
        httpd.server_close()
    print("✓ Asistente cerrado.", flush=True)


if __name__ == "__main__":
    main()
