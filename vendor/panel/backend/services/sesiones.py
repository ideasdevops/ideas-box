"""
Sesiones de Claude Code en la terminal, para mirarlas desde el panel.

Claude Code guarda cada sesión en ~/.claude/projects/<carpeta>/<sesion>.jsonl. El
panel solo LEE esos archivos (nunca los escribe ni manda nada a la sesión) y los
traduce a lo que le interesa a una persona: qué se pidió, qué respondió el agente
y qué herramientas usó (comandos, archivos, búsquedas). Es un control visual de
lo que pasa en la terminal, no un control remoto.
"""
import json
import time
from datetime import datetime
from pathlib import Path

from db import db_session

PROJECTS = Path.home() / ".claude" / "projects"
ACTIVA_SEG = 120          # sin cambios en 2 minutos: se considera en pausa
VENTANA_H = 72            # se listan las sesiones de los últimos 3 días
MAX_ENTRADAS = 400


def _ids_del_panel() -> set[str]:
    with db_session() as conn:
        return {r[0] for r in conn.execute("SELECT session_id FROM runs WHERE session_id IS NOT NULL")}


def _texto(contenido) -> str:
    if isinstance(contenido, str):
        return contenido
    if isinstance(contenido, list):
        return " ".join(c.get("text", "") for c in contenido if isinstance(c, dict) and c.get("type") == "text")
    return ""


def _ruido(texto: str) -> bool:
    """Mensajes internos que Claude Code guarda como si fueran del usuario."""
    t = texto.strip()
    return (not t) or t.startswith(("<command-", "<local-command", "<system-reminder", "Caveat:", "[Request interrupted"))


def _hora_local(ts: str) -> str:
    """Claude Code guarda las horas en UTC («…Z»): se muestran en la hora del equipo."""
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%H:%M:%S")
    except ValueError:
        return ts[11:19]


def _resumen_tool(nombre: str, entrada: dict) -> str:
    for k in ("command", "file_path", "path", "pattern", "query", "url", "description"):
        if entrada.get(k):
            return str(entrada[k]).replace("\n", " ")[:200]
    return ""


def listar() -> list[dict]:
    if not PROJECTS.exists():
        return []
    panel = _ids_del_panel()
    limite = time.time() - VENTANA_H * 3600
    out = []
    for f in PROJECTS.glob("*/*.jsonl"):
        try:
            st = f.stat()
        except OSError:
            continue
        if st.st_mtime < limite:
            continue
        titulo, cwd, mensajes = "", "", 0
        with open(f, encoding="utf-8", errors="replace") as fh:
            for linea in fh:
                try:
                    d = json.loads(linea)
                except json.JSONDecodeError:
                    continue
                cwd = cwd or d.get("cwd", "")
                if d.get("type") == "user" and not d.get("isMeta"):
                    tx = _texto(d.get("message", {}).get("content"))
                    if not _ruido(tx):
                        mensajes += 1
                        titulo = titulo or tx.strip().replace("\n", " ")[:120]
                elif d.get("type") == "assistant":
                    mensajes += 1
        out.append({
            "id": f.stem,
            "titulo": titulo or "(sin pedido todavía)",
            "carpeta": cwd,
            "actualizada": time.strftime("%Y-%m-%d %H:%M", time.localtime(st.st_mtime)),
            "activa": time.time() - st.st_mtime < ACTIVA_SEG,
            "origen": "panel" if f.stem in panel else "terminal",
            "mensajes": mensajes,
        })
    out.sort(key=lambda s: s["actualizada"], reverse=True)
    return out


def detalle(session_id: str, desde: int = 0) -> dict | None:
    # El id viene de la URL: solo se acepta el nombre exacto de un archivo existente
    candidatos = [f for f in PROJECTS.glob("*/*.jsonl") if f.stem == session_id] if PROJECTS.exists() else []
    if not candidatos:
        return None
    f = candidatos[0]
    with open(f, encoding="utf-8", errors="replace") as fh:
        lineas = fh.readlines()
    entradas = []
    for i, linea in enumerate(lineas[desde:], start=desde):
        try:
            d = json.loads(linea)
        except json.JSONDecodeError:
            continue
        hora = _hora_local(d.get("timestamp") or "")
        msg = d.get("message") or {}
        if d.get("type") == "user" and not d.get("isMeta"):
            contenido = msg.get("content")
            if isinstance(contenido, list) and any(c.get("type") == "tool_result" for c in contenido if isinstance(c, dict)):
                for c in contenido:
                    if isinstance(c, dict) and c.get("type") == "tool_result":
                        tx = c.get("content")
                        tx = _texto(tx) if not isinstance(tx, str) else tx
                        entradas.append({"n": i + 1, "hora": hora, "tipo": "resultado", "texto": (tx or "")[:400],
                                         "error": bool(c.get("is_error"))})
            else:
                tx = _texto(contenido)
                if not _ruido(tx):
                    entradas.append({"n": i + 1, "hora": hora, "tipo": "pedido", "texto": tx[:3000]})
        elif d.get("type") == "assistant":
            for c in msg.get("content") or []:
                if c.get("type") == "text" and c.get("text", "").strip():
                    entradas.append({"n": i + 1, "hora": hora, "tipo": "texto", "texto": c["text"][:4000]})
                elif c.get("type") == "tool_use":
                    entradas.append({"n": i + 1, "hora": hora, "tipo": "herramienta", "herramienta": c.get("name", ""),
                                     "texto": _resumen_tool(c.get("name", ""), c.get("input") or {})})
    if desde == 0 and len(entradas) > MAX_ENTRADAS:
        entradas = entradas[-MAX_ENTRADAS:]
    activa = time.time() - f.stat().st_mtime < ACTIVA_SEG
    return {"id": session_id, "entradas": entradas, "siguiente": len(lineas), "activa": activa}
