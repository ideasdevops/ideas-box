"""
Los servidores no se listan a mano: salen de los conectores MCP realmente
instalados (`mcp-installed.tsv`). Un servidor es la unión de los conectores que
comparten etiqueta — típicamente uno de SSH y uno de panel de servicios.

Consecuencia buscada: instalar un conector nuevo con `ideasbox mcp add` lo hace
aparecer en el panel sin tocar código ni configuración.
"""
from fastapi import APIRouter

from config import SERVER_TOOLGROUPS, mcp_installed

router = APIRouter(prefix="/api/servers", tags=["servers"])


def server_roster() -> list:
    por_alias = {}
    for fila in mcp_installed():
        if fila["toolgroup"] not in SERVER_TOOLGROUPS:
            continue
        # La etiqueta es lo que distingue una máquina de otra. Un conector sin
        # etiqueta (instancia única) se identifica por su propio id.
        alias = fila["etiqueta"] or fila["id"]
        entrada = por_alias.setdefault(
            alias, {"alias": alias, "label": alias, "mcps": [], "toolgroups": []}
        )
        entrada["mcps"].append(fila["servidor"])
        if fila["toolgroup"] not in entrada["toolgroups"]:
            entrada["toolgroups"].append(fila["toolgroup"])
    return [por_alias[k] for k in sorted(por_alias)]


def find_server(alias_or_label: str) -> dict | None:
    if not alias_or_label:
        return None
    needle = alias_or_label.strip().lower()
    for server in server_roster():
        if server["alias"].lower() == needle or server["label"].lower() == needle:
            return server
    return None


@router.get("")
def list_servers():
    roster = server_roster()
    return {"total": len(roster), "servers": roster}
