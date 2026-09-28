from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware

from db import init_db
from config import DATA_ROOT, EMPRESA_NOMBRE, EMPRESA_RESPONSABLE, EMPRESA_RUBRO, EMPRESA_SITIO
from routers import agents, skills, tasks, servers, chat, runs, hilos, sesiones, programacion, mantenimiento
from services import scheduler

app = FastAPI(title=f"Panel de {EMPRESA_NOMBRE}", version="0.1.0")

# Local-only, un solo usuario -- CORS abierto para el dev server de Vite (localhost:5173).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
)

init_db()

app.include_router(agents.router)
app.include_router(skills.router)
app.include_router(tasks.router)
app.include_router(servers.router)
app.include_router(chat.router)
app.include_router(runs.router)
app.include_router(hilos.router)
app.include_router(sesiones.router)
app.include_router(programacion.router)
app.include_router(mantenimiento.router)

# Planificador y ejecutor arrancan con el panel (las programaciones corren mientras esté abierto)
scheduler.iniciar()


@app.get("/api/health")
def health():
    return {"ok": True}


@app.get("/api/profile")
def profile():
    """Identidad de la empresa: el panel se rotula con ella, no con una marca fija."""
    from services.runner import claude_bin  # noqa: PLC0415
    return {"empresa": EMPRESA_NOMBRE, "rubro": EMPRESA_RUBRO, "sitio": EMPRESA_SITIO,
            "responsable": EMPRESA_RESPONSABLE, "claude": bool(claude_bin()), "raiz": str(DATA_ROOT)}


_FRONTEND_DIST = Path(__file__).resolve().parent.parent / "frontend" / "dist"
if _FRONTEND_DIST.exists():
    # La interfaz es una SPA: /conversar, /tareas… son rutas del navegador. Cualquier ruta
    # que no sea de la API ni un archivo real devuelve index.html (antes, recargar o abrir
    # un enlace directo daba «Not Found»).
    _DIST = _FRONTEND_DIST.resolve()

    @app.get("/{ruta:path}", include_in_schema=False)
    def spa(ruta: str):
        if ruta.startswith("api/"):
            raise HTTPException(404, "no existe")
        archivo = (_DIST / ruta).resolve()
        if ruta and archivo.is_file() and archivo.is_relative_to(_DIST):
            return FileResponse(archivo)
        return FileResponse(_DIST / "index.html", headers={"Cache-Control": "no-cache"})
