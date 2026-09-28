"""
Mantenimiento de Ideas Box desde el panel, sin terminal: las mismas acciones del
menú (revisar, actualizar, respaldar, conectar herramientas, sumar habilidades…),
corridas con `ideasbox` en la fila de mantenimiento y con la salida en vivo.

Solo acciones de una lista cerrada: el panel no ejecuta comandos arbitrarios.
Las credenciales de un conector llegan en el pedido y pasan al instalador como
IB_ANS_cred_<id>_<CLAVE> (el mismo mecanismo del asistente de instalación): van
directo a su archivo con permisos 600 y no quedan en el historial.
"""
import os
import re
import shlex
import subprocess
import threading
import time
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from config import MCP_REGISTRY
from services.runner import IDEASBOX, _stack_src, runner

router = APIRouter(prefix="/api/mantenimiento", tags=["mantenimiento"])

ACCIONES = {
    "revisar": ("Revisar que todo esté bien", ["doctor"]),
    "revisar-profundo": ("Revisión profunda (prueba cada conector)", ["doctor", "--deep"]),
    "sincronizar": ("Regenerar agentes y reparar enlaces", ["sync"]),
    "actualizar": ("Actualizar Ideas Box, habilidades y conectores", ["update"]),
    "actualizar-habilidades": ("Actualizar las habilidades", ["skills", "update"]),
    "respaldo": ("Hacer un respaldo", ["backup"]),
    "iconos": ("Rehacer los íconos del Escritorio", ["icono"]),
    "actualizar-panel": ("Actualizar el panel a la última versión", ["panel", "install"]),
}


class Pedido(BaseModel):
    accion: str
    pack: str | None = None
    conector: str | None = None
    etiqueta: str | None = None
    claves: dict[str, str] | None = None
    login: bool = True
    servidor: str | None = None


def _ideasbox(*args: str, timeout: int = 20) -> str:
    try:
        r = subprocess.run(["bash", str(IDEASBOX), *args], capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL, env=dict(os.environ, NO_COLOR="1"))
        return (r.stdout or "").strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def autostart_activo() -> bool:
    return _ideasbox("panel", "autostart", "status").splitlines()[-1:] == ["on"]


def _parse_mcp(path: Path) -> dict:
    d = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([A-Z_][A-Z0-9_]*)=(.*)$", line.strip())
        if m:
            try:
                d[m.group(1)] = " ".join(shlex.split(m.group(2), comments=True))
            except ValueError:
                d[m.group(1)] = m.group(2).strip("\"'")
    return d


def _catalogo() -> dict:
    src = _stack_src()
    instalados = {}
    if MCP_REGISTRY.exists():
        for raw in MCP_REGISTRY.read_text(encoding="utf-8").splitlines():
            cols = raw.split("\t")
            if len(cols) >= 2:
                instalados.setdefault(cols[1], []).append(cols[0])
    conectores, packs = [], []
    if src and (src / "catalog" / "mcp").exists():
        for f in sorted((src / "catalog" / "mcp").glob("*.mcp")):
            d = _parse_mcp(f)
            keys = d.get("ENV_KEYS", "").split()
            secret = set(d.get("ENV_SECRET", "").split())
            conectores.append({
                "id": d.get("ID", f.stem), "titulo": d.get("TITLE", f.stem), "descripcion": d.get("DESC", ""),
                "nivel": d.get("TIER", ""), "recomendado": d.get("RECOMMENDED") == "1", "multi": d.get("MULTI") == "1",
                "etiqueta": d.get("INSTANCE_PROMPT", ""), "login": bool(d.get("LOGIN_CMD")), "tipo": d.get("KIND", ""),
                "campos": [{"clave": k, "texto": d.get(f"ENV_PROMPT_{k}", k), "secreto": k in secret} for k in keys],
                "instalado": instalados.get(d.get("ID", f.stem), []),
            })
        tsv = src / "catalog" / "skill-packs.tsv"
        if tsv.exists():
            for line in tsv.read_text(encoding="utf-8").splitlines():
                cols = line.split("\t")
                if line.startswith("#") or len(cols) < 6 or cols[1] == "conector":
                    continue
                packs.append({"id": cols[0], "nivel": cols[1], "area": cols[2], "descripcion": cols[5]})
    return {"conectores": conectores, "packs": packs}


@router.get("")
def estado():
    return {
        "acciones": [{"id": k, "titulo": v[0]} for k, v in ACCIONES.items()],
        "autostart": autostart_activo(),
        **_catalogo(),
    }


@router.post("")
def ejecutar(p: Pedido):
    env: dict[str, str] = {}
    if p.accion in ACCIONES:
        titulo, args = ACCIONES[p.accion]
    elif p.accion == "sumar-habilidad" and p.pack and re.fullmatch(r"[a-z0-9-]+", p.pack):
        titulo, args = f"Sumar las habilidades «{p.pack}»", ["skills", "add", p.pack]
    elif p.accion == "conectar" and p.conector and re.fullmatch(r"[a-z0-9-]+", p.conector):
        titulo, args = f"Conectar {p.conector}", ["mcp", "add", p.conector]
        if p.etiqueta:
            args.append(re.sub(r"[^a-z0-9-]", "-", p.etiqueta.lower())[:40])
        cid = re.sub(r"[^A-Za-z0-9_]", "_", p.conector)
        claves = {k: v for k, v in (p.claves or {}).items() if re.fullmatch(r"[A-Z0-9_]+", k)}
        env[f"IB_ANS_reuse_{cid}"] = "n" if any(claves.values()) else "s"
        for k, v in claves.items():
            env[f"IB_ANS_cred_{cid}_{k}"] = v
        env[f"IB_ANS_login_{cid}"] = "s" if p.login else "n"
        env[f"IB_ANS_mcp_more_{cid}"] = "n"
    elif p.accion == "quitar-conector" and p.servidor and re.fullmatch(r"[a-z0-9-]+", p.servidor):
        titulo, args = f"Quitar el conector {p.servidor}", ["mcp", "remove", p.servidor]
        env["ASSUME_YES"] = "1"
    else:
        raise HTTPException(400, "acción desconocida")
    run_id = runner().encolar_mantenimiento(titulo=titulo, accion=p.accion, args=args, env_extra=env)
    return {"run_id": run_id}


class Autostart(BaseModel):
    activo: bool


@router.post("/autostart")
def cambiar_autostart(a: Autostart):
    salida = _ideasbox("panel", "autostart", "on" if a.activo else "off", timeout=60)
    return {"autostart": autostart_activo(), "detalle": salida[-400:]}


@router.post("/reiniciar")
def reiniciar():
    """Reinicia el panel (después de actualizarlo). Responde antes de irse."""
    def _mas_tarde():
        time.sleep(1)
        subprocess.Popen(["bash", "-c", f"sleep 1; bash {shlex.quote(str(IDEASBOX))} panel restart"],
                         start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    threading.Thread(target=_mas_tarde, daemon=True).start()
    return {"ok": True}


class Ajustes(BaseModel):
    modelo: str | None = None
    max_turnos: int | None = None


@router.get("/ajustes")
def ver_ajustes():
    from db import ajuste  # noqa: PLC0415
    return {"modelo": ajuste("modelo", ""), "max_turnos": int(ajuste("max_turnos", "40") or 40)}


@router.post("/ajustes")
def cambiar_ajustes(a: Ajustes):
    from db import guardar_ajuste  # noqa: PLC0415
    if a.modelo is not None:
        if a.modelo not in ("", "sonnet", "opus", "haiku"):
            raise HTTPException(400, "modelo desconocido")
        guardar_ajuste("modelo", a.modelo)
    if a.max_turnos is not None:
        guardar_ajuste("max_turnos", str(min(max(a.max_turnos, 5), 200)))
    return ver_ajustes()
