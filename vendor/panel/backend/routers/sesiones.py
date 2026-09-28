"""Sesiones de Claude Code en la terminal, solo lectura (ver services/sesiones.py)."""
from fastapi import APIRouter, HTTPException

from services import sesiones

router = APIRouter(prefix="/api/sesiones", tags=["sesiones"])


@router.get("")
def listar():
    return {"sesiones": sesiones.listar()}


@router.get("/{session_id}")
def detalle(session_id: str, desde: int = 0):
    d = sesiones.detalle(session_id, desde)
    if d is None:
        raise HTTPException(404, "sesión no encontrada")
    return d
