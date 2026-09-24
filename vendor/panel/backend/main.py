from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from db import init_db
from config import EMPRESA_NOMBRE, EMPRESA_RUBRO, EMPRESA_SITIO
from routers import agents, skills, tasks, servers, chat, execution

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
app.include_router(execution.router)


@app.get("/api/health")
def health():
    return {"ok": True}


@app.get("/api/profile")
def profile():
    """Identidad de la empresa: el panel se rotula con ella, no con una marca fija."""
    return {"empresa": EMPRESA_NOMBRE, "rubro": EMPRESA_RUBRO, "sitio": EMPRESA_SITIO}


_FRONTEND_DIST = Path(__file__).resolve().parent.parent / "frontend" / "dist"
if _FRONTEND_DIST.exists():
    app.mount("/", StaticFiles(directory=str(_FRONTEND_DIST), html=True), name="frontend")
