import sqlite3
from contextlib import contextmanager

from config import PANEL_DATA_DIR, PANEL_DB_PATH

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    titulo TEXT NOT NULL,
    descripcion TEXT DEFAULT '',
    agente_sugerido TEXT DEFAULT '',
    server_objetivo TEXT DEFAULT '',
    prioridad TEXT NOT NULL DEFAULT 'media' CHECK(prioridad IN ('baja','media','alta')),
    estado TEXT NOT NULL DEFAULT 'pendiente' CHECK(estado IN ('pendiente','en_progreso','listo_para_revision','hecho','descartada')),
    programada_para TEXT,
    recurrencia TEXT NOT NULL DEFAULT 'ninguna' CHECK(recurrencia IN ('ninguna','diaria','semanal','mensual')),
    proximo_vencimiento TEXT,
    auto_publicar INTEGER NOT NULL DEFAULT 0 CHECK(auto_publicar IN (0,1)),
    resultado_ejecucion TEXT,
    fuente TEXT NOT NULL DEFAULT 'manual' CHECK(fuente IN ('manual','chat')),
    pr_url TEXT,
    creada_en TEXT NOT NULL DEFAULT (datetime('now')),
    actualizada_en TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS task_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    titulo TEXT NOT NULL,
    descripcion TEXT DEFAULT '',
    agente_sugerido TEXT DEFAULT ''
);

-- Historial simple del chat de interpretacion -- una sola conversacion continua,
-- herramienta de un solo usuario, sin sesiones/multiusuario.
CREATE TABLE IF NOT EXISTS chat_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rol TEXT NOT NULL CHECK(rol IN ('usuario','asistente')),
    texto TEXT NOT NULL,
    tarea_creada_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
    creado_en TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Ejecuciones: cada vez que el panel corre algo (un agente con Claude Code, un
-- mensaje de conversación o una acción de mantenimiento de ideasbox). La salida
-- en vivo va a un archivo por ejecución (PANEL_DATA_DIR/runs/<id>.jsonl).
CREATE TABLE IF NOT EXISTS runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tipo TEXT NOT NULL CHECK(tipo IN ('tarea','chat','mantenimiento')),
    titulo TEXT NOT NULL,
    prompt TEXT DEFAULT '',
    agente TEXT DEFAULT '',
    modo TEXT NOT NULL DEFAULT 'carpeta' CHECK(modo IN ('carpeta','analizar')),
    tarea_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
    hilo_id INTEGER REFERENCES hilos(id) ON DELETE CASCADE,
    accion TEXT DEFAULT '',
    estado TEXT NOT NULL DEFAULT 'en_cola' CHECK(estado IN ('en_cola','corriendo','ok','error','cancelado')),
    origen TEXT NOT NULL DEFAULT 'manual' CHECK(origen IN ('manual','programada')),
    session_id TEXT,
    resultado TEXT,
    bloqueos TEXT,
    costo_usd REAL,
    turnos INTEGER,
    revisado INTEGER NOT NULL DEFAULT 0,
    creada_en TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    inicio TEXT,
    fin TEXT
);

-- Conversaciones con un agente: cada mensaje es una ejecución que retoma la sesión
-- de Claude Code anterior (--resume), así el agente recuerda el hilo.
CREATE TABLE IF NOT EXISTS hilos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agente TEXT NOT NULL,
    titulo TEXT NOT NULL,
    modo TEXT NOT NULL DEFAULT 'carpeta' CHECK(modo IN ('carpeta','analizar')),
    session_id TEXT,
    creado_en TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    actualizado_en TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS recordatorios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    texto TEXT NOT NULL,
    cuando TEXT,
    hecho INTEGER NOT NULL DEFAULT 0 CHECK(hecho IN (0,1)),
    creado_en TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS ajustes (
    clave TEXT PRIMARY KEY,
    valor TEXT
);
"""

# Columnas agregadas después de la primera versión: los paneles ya instalados tienen
# la tabla sin ellas, y SQLite no tiene "ADD COLUMN IF NOT EXISTS".
MIGRACIONES = {
    "tasks": [
        ("ejecucion", "TEXT NOT NULL DEFAULT 'manual'"),   # manual (recordar) | auto (ejecutar sola)
        ("modo", "TEXT NOT NULL DEFAULT 'carpeta'"),        # carpeta | analizar
        ("ultima_ejecucion_id", "INTEGER"),
        ("avisada", "INTEGER NOT NULL DEFAULT 0"),
    ],
}

SEED_TEMPLATES = [
    (
        "Corregir un bug",
        "Corregir <bug> en <proyecto>",
        "Reproducir primero, escribir el caso de prueba que falla y recién después tocar código. "
        "Seguir dev/bugfix-workflow.",
        "dev-saas",
    ),
    (
        "Publicar una versión",
        "Release de <proyecto> <versión>",
        "Validar con qa/release-validation, seguir dev/release-workflow y dev/deploy-checklist. "
        "El deploy a producción se confirma con una persona antes de ejecutarlo.",
        "dev-saas",
    ),
    (
        "Revisar servicios",
        "Revisar estado de servicios en <servidor>",
        "Estado, logs y métricas con ops/servicios-monitor. Lectura es libre; reiniciar o "
        "detener un servicio requiere aprobación explícita.",
        "ops-support",
    ),
    (
        "Backup de bases de datos",
        "Backup de bases de datos de los servidores conectados",
        "Recorrer los servidores del panel y bajar el backup de cada base (requiere aprobación "
        "explícita por servidor). Confirmar que cada backup terminó bien antes de cerrar la tarea. "
        "Marcar recurrencia mensual al crear.",
        "ops-support",
    ),
    (
        "Auditoría de seguridad",
        "Auditar seguridad de <proyecto>",
        "Revisión de dependencias, secretos expuestos y superficie pública. Si está instalado el "
        "pack de skills de seguridad ofensiva, correrlo SIEMPRE contra staging, nunca contra "
        "producción sin confirmación explícita.",
        "qa-tester",
    ),
    (
        "Seguimiento de cliente",
        "Seguimiento de <cliente>",
        "Estado del proyecto, próximos pasos y continuidad, con clientes/customer-followup. "
        "Dejar el registro en la memoria del stack.",
        "customer-success-pm",
    ),
    (
        "Propuesta comercial",
        "Propuesta para <prospecto>",
        "Armar alcance, precio y condiciones con ventas/sales-proposal. Enviarla al cliente "
        "requiere aprobación explícita.",
        "sales-crm",
    ),
    (
        "Creación de contenidos",
        "Crear contenido para <canal>",
        "Guion, copy y piezas con contenido/social-post y contenido/content-calendar. "
        "Publicar en las redes conectadas lo hace una persona: el panel redacta, no publica.",
        "content-strategist",
    ),
    (
        "Optimización SEO",
        "Optimizar SEO de <sitio o página>",
        "Auditoría técnica, contenido y datos estructurados con el pack de skills de marketing. "
        "Confirmar el sitio exacto antes de tocar nada en producción.",
        "growth-marketing",
    ),
    (
        "Gestión de comunidad",
        "Gestionar la comunidad de <canal>",
        "Responder comentarios y moderar. Enviar mensajes directos a una persona NUNCA se hace "
        "sin autorización explícita del usuario.",
        "content-strategist",
    ),
    (
        "Bitácora y memoria",
        "Actualizar la memoria del stack sobre <tema>",
        "Consolidar lo aprendido con core/docs-memory-sync para que sobreviva a la sesión.",
        "docs-memory",
    ),
]


def get_connection() -> sqlite3.Connection:
    PANEL_DATA_DIR.mkdir(parents=True, exist_ok=True)
    # Varios hilos (planificador, ejecuciones, pedidos web) escriben la misma base
    conn = sqlite3.connect(PANEL_DB_PATH, timeout=15, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db() -> None:
    conn = get_connection()
    try:
        conn.executescript(SCHEMA)
        for tabla, columnas in MIGRACIONES.items():
            existentes_cols = {r[1] for r in conn.execute(f"PRAGMA table_info({tabla})")}
            for nombre, definicion in columnas:
                if nombre not in existentes_cols:
                    conn.execute(f"ALTER TABLE {tabla} ADD COLUMN {nombre} {definicion}")
        # Una ejecución que quedó "corriendo" o "en cola" cuando se cerró el panel ya no
        # corre: se marca así en vez de quedar colgada para siempre.
        conn.execute(
            "UPDATE runs SET estado = 'cancelado', fin = datetime('now','localtime'), "
            "resultado = COALESCE(resultado, 'Se interrumpió porque el panel se cerró.') "
            "WHERE estado IN ('corriendo','en_cola')"
        )
        # Idempotente por nombre -- agrega templates nuevos de SEED_TEMPLATES sin duplicar
        # ni pisar los que ya existen (el usuario puede haber editado uno a mano).
        existentes = {row[0] for row in conn.execute("SELECT nombre FROM task_templates")}
        nuevos = [t for t in SEED_TEMPLATES if t[0] not in existentes]
        if nuevos:
            conn.executemany(
                "INSERT INTO task_templates (nombre, titulo, descripcion, agente_sugerido) VALUES (?, ?, ?, ?)",
                nuevos,
            )
        conn.commit()
    finally:
        conn.close()


def ajuste(clave: str, defecto: str = "") -> str:
    with db_session() as conn:
        row = conn.execute("SELECT valor FROM ajustes WHERE clave = ?", (clave,)).fetchone()
        return row[0] if row and row[0] is not None else defecto


def guardar_ajuste(clave: str, valor: str) -> None:
    with db_session() as conn:
        conn.execute("INSERT INTO ajustes (clave, valor) VALUES (?, ?) ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor", (clave, valor))


@contextmanager
def db_session():
    conn = get_connection()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()
