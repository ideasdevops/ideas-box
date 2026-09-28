"""Programación: en curso, en cola, próximas, vencidas, recomendaciones y recordatorios."""
from datetime import datetime, timedelta

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from db import db_session
from routers.mantenimiento import autostart_activo
from services import recomendaciones
from services.scheduler import parse_fecha, siguiente

router = APIRouter(prefix="/api", tags=["programacion"])


class RecordatorioNuevo(BaseModel):
    texto: str
    cuando: str | None = None


def _proximas(tareas: list[dict], dias: int = 14) -> list[dict]:
    """Próximas ocurrencias de las tareas programadas (las recurrentes se repiten)."""
    ahora, hasta = datetime.now(), datetime.now() + timedelta(days=dias)
    out = []
    for t in tareas:
        cuando = parse_fecha(t.get("programada_para"))
        if not cuando or t["estado"] in ("hecho", "descartada"):
            continue
        n = 0
        while cuando <= hasta and n < 31:
            if cuando > ahora:
                out.append({"tarea_id": t["id"], "titulo": t["titulo"], "agente": t["agente_sugerido"],
                            "cuando": cuando.strftime("%Y-%m-%dT%H:%M"), "ejecucion": t["ejecucion"],
                            "modo": t["modo"], "recurrencia": t["recurrencia"]})
            if t["recurrencia"] == "ninguna":
                break
            cuando = siguiente(cuando, t["recurrencia"])
            n += 1
    out.sort(key=lambda x: x["cuando"])
    return out


@router.get("/programacion")
def programacion():
    with db_session() as conn:
        corriendo = [dict(r) for r in conn.execute("SELECT * FROM runs WHERE estado = 'corriendo' ORDER BY inicio")]
        en_cola = [dict(r) for r in conn.execute("SELECT * FROM runs WHERE estado = 'en_cola' ORDER BY id")]
        tareas = [dict(r) for r in conn.execute("SELECT * FROM tasks")]
        recientes = [dict(r) for r in conn.execute(
            "SELECT * FROM runs WHERE estado IN ('ok','error','cancelado') ORDER BY id DESC LIMIT 8")]
        recordatorios = [dict(r) for r in conn.execute("SELECT * FROM recordatorios WHERE hecho = 0 ORDER BY cuando IS NULL, cuando")]
    ahora = datetime.now()
    vencidas = [
        t for t in tareas
        if t["estado"] == "pendiente" and (c := parse_fecha(t.get("programada_para"))) and c <= ahora and t["ejecucion"] != "auto"
    ]
    auto = autostart_activo()
    return {
        "corriendo": corriendo,
        "en_cola": en_cola,
        "proximas": _proximas(tareas),
        "vencidas": vencidas,
        "recientes": recientes,
        "recordatorios": recordatorios,
        "sugerencias": recomendaciones.calcular(auto),
        "autostart": auto,
        "ahora": ahora.strftime("%Y-%m-%dT%H:%M"),
    }


@router.post("/recordatorios")
def crear_recordatorio(r: RecordatorioNuevo):
    if not r.texto.strip():
        raise HTTPException(400, "falta el texto")
    with db_session() as conn:
        cur = conn.execute("INSERT INTO recordatorios (texto, cuando) VALUES (?, ?)", (r.texto.strip(), r.cuando or None))
        return dict(conn.execute("SELECT * FROM recordatorios WHERE id = ?", (cur.lastrowid,)).fetchone())


@router.post("/recordatorios/{rid}/hecho")
def recordatorio_hecho(rid: int):
    with db_session() as conn:
        conn.execute("UPDATE recordatorios SET hecho = 1 WHERE id = ?", (rid,))
    return {"ok": True}


@router.delete("/recordatorios/{rid}")
def borrar_recordatorio(rid: int):
    with db_session() as conn:
        conn.execute("DELETE FROM recordatorios WHERE id = ?", (rid,))
    return {"ok": True}
