"""
Configuración del panel: sale del perfil del stack, nunca de rutas fijas.

La raíz de datos la elige el usuario al instalar (un disco, una partición o una
carpeta del home), así que acá no se hardcodea ningún punto de montaje: se lee
de `~/.config/ideasbox/empresa.conf`, el mismo archivo que usan el instalador y
el CLI.
"""
import os
from pathlib import Path

STACK_NAME = os.environ.get("IDEASBOX_STACK_NAME", "ideasbox")
STACK_CONFIG_DIR = Path(
    os.environ.get("IDEASBOX_CONFIG_DIR", Path.home() / ".config" / STACK_NAME)
)
STACK_PROFILE = STACK_CONFIG_DIR / "empresa.conf"

# Registro de conectores MCP realmente instalados, escrito por lib/mcp.sh.
# Formato: servidor \t id \t grupo-de-herramientas \t etiqueta
MCP_REGISTRY = STACK_CONFIG_DIR / "mcp-installed.tsv"

PANEL_ENV_PATH = STACK_CONFIG_DIR / "secrets" / "panel.env"


def _read_shell_conf(path: Path) -> dict:
    """Lee un archivo KEY="valor" de shell. Mismo formato que empresa.conf."""
    data = {}
    if not path.exists():
        return data
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


_PROFILE = _read_shell_conf(STACK_PROFILE)


def _profile_value(key: str, default: str = "") -> str:
    # La variable de entorno gana: así el CLI puede levantar el panel contra
    # otro perfil sin tocar el archivo.
    return os.environ.get(key) or _PROFILE.get(key, default)


EMPRESA_NOMBRE = _profile_value("EMPRESA_NOMBRE", "tu empresa")
EMPRESA_SLUG = _profile_value("EMPRESA_SLUG", "empresa")
EMPRESA_RUBRO = _profile_value("EMPRESA_RUBRO", "")
EMPRESA_SITIO = _profile_value("EMPRESA_SITIO", "")
EMPRESA_RESPONSABLE = _profile_value("EMPRESA_RESPONSABLE", "")
EMPRESA_IDIOMA = _profile_value("EMPRESA_IDIOMA", "es")
EMPRESA_TZ = _profile_value("EMPRESA_TZ", "")


def resolve_data_root() -> Path:
    valor = _profile_value("DATA_ROOT")
    if not valor:
        raise RuntimeError(
            f"No encuentro el perfil del stack en {STACK_PROFILE}. "
            f"Corré el instalador de {STACK_NAME}, o definí DATA_ROOT."
        )
    return Path(valor).expanduser()


DATA_ROOT = resolve_data_root()
CLAUDE_DIR = DATA_ROOT / ".claude"
AGENTS_DIR = CLAUDE_DIR / "agents"
SKILLS_DIR = CLAUDE_DIR / "skills"

AGENT_DOMAINS = ["core", "dev", "ops", "qa", "ventas", "marketing", "contenido", "clientes", "internos"]
SKILL_DOMAINS = AGENT_DOMAINS  # mismos 9 dominios, misma convención

# Las tareas son datos de la empresa, no estado de la aplicación: viven en la
# raíz de datos, que es lo que el usuario respalda y puede mover de máquina.
PANEL_DATA_DIR = DATA_ROOT / "05-OPERACIONES" / "panel"
PANEL_DB_PATH = PANEL_DATA_DIR / "panel.db"


def mcp_installed() -> list:
    """Conectores MCP instalados, leídos del registro del stack."""
    filas = []
    if not MCP_REGISTRY.exists():
        return filas
    for raw in MCP_REGISTRY.read_text(encoding="utf-8", errors="replace").splitlines():
        if not raw.strip() or raw.startswith("#"):
            continue
        partes = raw.split("\t")
        if len(partes) < 3:
            continue
        servidor, mcp_id, toolgroup = partes[0], partes[1], partes[2]
        etiqueta = partes[3] if len(partes) > 3 else ""
        filas.append(
            {"servidor": servidor, "id": mcp_id, "toolgroup": toolgroup, "etiqueta": etiqueta}
        )
    return filas


# Grupos de herramientas que representan una máquina administrable. Un servidor
# del panel es la unión de los conectores que comparten etiqueta.
SERVER_TOOLGROUPS = ["ssh", "easypanel"]
