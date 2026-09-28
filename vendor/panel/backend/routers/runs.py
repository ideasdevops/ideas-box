"""Ejecuciones (agentes y mantenimiento): listado, detalle, salida en vivo y control."""
import asyncio
import json
from typing import Literal

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from db import db_session
from services.runner import leer_eventos, runner

router = APIRouter(prefix="/api/runs", tags=["runs"])

FINALES = ("ok", "error", "cancelado")


class RunNueva(BaseModel):
    agente: str = ""
    pedido: str
    modo: Literal["carpeta", "analizar"] = "carpeta"
    titulo: str = ""


def _run(run_id: int) -> dict:
    with db_session() as conn:
        row = conn.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
    if not row:
        raise HTTPException(404, "ejecución no encontrada")
    return dict(row)


@router.get("")
def listar(estado: str | None = None, tipo: str | None = None, limite: int = 50):
    q, params, where = "SELECT * FROM runs", [], []
    if estado:
        where.append("estado IN (%s)" % ",".join("?" * len(estado.split(","))))
        params += estado.split(",")
    if tipo:
        where.append("tipo = ?")
        params.append(tipo)
    if where:
        q += " WHERE " + " AND ".join(where)
    q += " ORDER BY id DESC LIMIT ?"
    params.append(min(max(limite, 1), 500))
    with db_session() as conn:
        rows = [dict(r) for r in conn.execute(q, params)]
    return {"ejecuciones": rows}


@router.post("")
def crear(r: RunNueva):
    """Un pedido suelto a un agente (sin crear una tarea en el tablero)."""
    if not r.pedido.strip():
        raise HTTPException(400, "falta el pedido")
    titulo = r.titulo or r.pedido.strip().splitlines()[0][:120]
    run_id = runner().encolar_agente(tipo="tarea", titulo=titulo, prompt=r.pedido, agente=r.agente, modo=r.modo)
    return _run(run_id)


@router.get("/{run_id}")
def detalle(run_id: int):
    return {**_run(run_id), "eventos": leer_eventos(run_id)}


@router.get("/{run_id}/stream")
async def stream(run_id: int, desde: int = 0):
    _run(run_id)

    async def gen():
        n = desde
        while True:
            eventos = leer_eventos(run_id, n)
            for ev in eventos:
                n = ev["n"]
                yield f"data: {json.dumps(ev, ensure_ascii=False)}\n\n"
            if eventos and eventos[-1].get("tipo") == "fin":
                return
            if not eventos and _run(run_id)["estado"] in FINALES and not leer_eventos(run_id, n):
                yield f"data: {json.dumps({'tipo': 'fin', 'estado': _run(run_id)['estado'], 'n': n + 1})}\n\n"
                return
            yield ": sigo\n\n"
            await asyncio.sleep(0.7)

    return StreamingResponse(gen(), media_type="text/event-stream", headers={"Cache-Control": "no-store"})


@router.post("/{run_id}/cancelar")
def cancelar(run_id: int):
    if not runner().cancelar(run_id):
        raise HTTPException(409, "esa ejecución ya terminó")
    return {"ok": True}


@router.post("/{run_id}/revisado")
def revisado(run_id: int):
    _run(run_id)
    with db_session() as conn:
        conn.execute("UPDATE runs SET revisado = 1 WHERE id = ?", (run_id,))
    return {"ok": True}
