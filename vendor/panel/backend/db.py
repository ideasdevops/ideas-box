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

"""

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
    conn = sqlite3.connect(PANEL_DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db() -> None:
    conn = get_connection()
    try:
        conn.executescript(SCHEMA)
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


@contextmanager
def db_session():
    conn = get_connection()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()
