"""
Conversaciones con un agente desde el panel. Cada mensaje es una ejecución de
Claude Code que retoma la sesión anterior del hilo (--resume): el agente recuerda
lo conversado. Mismas reglas de permisos que las tareas (ver services/runner.py).
"""
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from db import db_session
from routers.agents import find_agent
from services.runner import leer_eventos, runner

router = APIRouter(prefix="/api/hilos", tags=["hilos"])


class HiloNuevo(BaseModel):
    agente: str
    modo: Literal["carpeta", "analizar"] = "carpeta"


class Mensaje(BaseModel):
    texto: str
    modo: Literal["carpeta", "analizar"] | None = None


def _hilo(hilo_id: int) -> dict:
    with db_session() as conn:
        row = conn.execute("SELECT * FROM hilos WHERE id = ?", (hilo_id,)).fetchone()
    if not row:
        raise HTTPException(404, "conversación no encontrada")
    return dict(row)


@router.get("")
def listar():
    with db_session() as conn:
        rows = [dict(r) for r in conn.execute(
            """SELECT h.*, (SELECT COUNT(*) FROM runs r WHERE r.hilo_id = h.id) AS mensajes,
                      (SELECT estado FROM runs r WHERE r.hilo_id = h.id ORDER BY id DESC LIMIT 1) AS ultimo_estado
               FROM hilos h ORDER BY actualizado_en DESC LIMIT 100""")]
    return {"hilos": rows}


@router.post("")
def crear(h: HiloNuevo):
    if not find_agent(h.agente):
        raise HTTPException(400, f"no existe el agente {h.agente}")
    with db_session() as conn:
        cur = conn.execute("INSERT INTO hilos (agente, titulo, modo) VALUES (?, ?, ?)", (h.agente, "Nueva conversación", h.modo))
        nuevo = cur.lastrowid
    return _hilo(nuevo)   # fuera del bloque: la fila ya quedó confirmada


@router.get("/{hilo_id}")
def detalle(hilo_id: int):
    hilo = _hilo(hilo_id)
    with db_session() as conn:
        runs = [dict(r) for r in conn.execute("SELECT * FROM runs WHERE hilo_id = ? ORDER BY id", (hilo_id,))]
    for r in runs:
        r["eventos"] = leer_eventos(r["id"])
    return {**hilo, "mensajes": runs}


@router.post("/{hilo_id}/mensaje")
def mensaje(hilo_id: int, m: Mensaje):
    hilo = _hilo(hilo_id)
    if not m.texto.strip():
        raise HTTPException(400, "mensaje vacío")
    with db_session() as conn:
        ocupado = conn.execute(
            "SELECT id FROM runs WHERE hilo_id = ? AND estado IN ('en_cola','corriendo')", (hilo_id,)).fetchone()
        if ocupado:
            raise HTTPException(409, "el agente todavía está respondiendo el mensaje anterior")
        modo = m.modo or hilo["modo"]
        if hilo["titulo"] == "Nueva conversación":
            conn.execute("UPDATE hilos SET titulo = ? WHERE id = ?", (m.texto.strip().splitlines()[0][:80], hilo_id))
        conn.execute("UPDATE hilos SET modo = ?, actualizado_en = datetime('now','localtime') WHERE id = ?", (modo, hilo_id))
    run_id = runner().encolar_agente(
        tipo="chat", titulo=m.texto.strip()[:120], prompt=m.texto, agente=hilo["agente"], modo=modo,
        hilo_id=hilo_id, resume=hilo["session_id"],
    )
    return {"run_id": run_id}


@router.delete("/{hilo_id}")
def borrar(hilo_id: int):
    _hilo(hilo_id)
    with db_session() as conn:
        conn.execute("DELETE FROM hilos WHERE id = ?", (hilo_id,))
    return {"ok": True}
