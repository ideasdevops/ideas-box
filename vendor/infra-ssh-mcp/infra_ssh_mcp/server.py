#!/usr/bin/env python3
"""
Infra SSH MCP Server.

Gives AI agents controlled SSH access to the Ubuntu 24 hosts behind
Easypanel: read-only Docker/system diagnostics run freely, mutating actions
(run_command, backup_database_to_local) are gated by agent policy -- always
require explicit user approval before use, per docs/OPERACIONES_08.md and the
agents' own instructions.
"""

import logging

from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

from .config import config
from . import tools

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

mcp = FastMCP(
    "infra-ssh-mcp",
    instructions=(
        f"SSH access to {config.client_label} ({config.host}). Read-only Docker/system "
        "tools run freely. run_command and backup_database_to_local always require "
        "explicit user approval before use -- never call them without it."
    ),
)


@mcp.tool(name="docker_ps", annotations=ToolAnnotations(readOnlyHint=True))
async def docker_ps() -> dict:
    """List all containers (running and stopped) on this server."""
    return await tools.docker_ps()


@mcp.tool(name="docker_logs", annotations=ToolAnnotations(readOnlyHint=True))
async def docker_logs(container_name: str, lines: int = 100) -> dict:
    """
    Get recent logs from a container.

    Args:
        container_name: exact container name, or "projectName_serviceName"
            (the live swarm replica suffix is resolved automatically)
        lines: number of trailing log lines (default 100)
    """
    return await tools.docker_logs(container_name, lines)


@mcp.tool(name="docker_stats", annotations=ToolAnnotations(readOnlyHint=True))
async def docker_stats() -> dict:
    """Snapshot of CPU/memory usage per running container."""
    return await tools.docker_stats()


@mcp.tool(name="system_info", annotations=ToolAnnotations(readOnlyHint=True))
async def system_info() -> dict:
    """Host uptime, disk usage and memory usage."""
    return await tools.system_info()


@mcp.tool(
    name="run_command",
    annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=True, idempotentHint=False),
)
async def run_command(command: str, timeout: float = 60.0) -> dict:
    """
    Run an arbitrary shell command on the server via SSH.

    REQUIRES EXPLICIT USER APPROVAL BEFORE EVERY CALL -- this can mutate or
    destroy anything on the host. Never call this without the user having
    approved this exact command first.

    Args:
        command: the shell command to run
        timeout: seconds before giving up (default 60)
    """
    return await tools.run_command(command, timeout)


@mcp.tool(
    name="backup_database_to_local",
    annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=False),
)
async def backup_database_to_local(
    project_name: str,
    service_name: str,
    db_type: str,
    db_user: str,
    db_name: str,
    db_password: str = "",
) -> dict:
    """
    Dump a database (postgres/mysql/mariadb) running in an Easypanel-managed
    container and save it directly to local disk under
    08-SCRIPTS -BKPs-en-SERVERS-CLIENTES/10-BACKUPS/<client>/<date>_<service>-backup/outputs/.
    Never staged on the remote server.

    REQUIRES EXPLICIT USER APPROVAL BEFORE EVERY CALL, per docs/OPERACIONES_08.md.

    Args:
        project_name: Easypanel project name (from easypanel-mcp)
        service_name: Easypanel service name (from easypanel-mcp)
        db_type: "postgres", "mysql", or "mariadb"
        db_user: database user (get via easypanel-mcp's get_service)
        db_name: database name (get via easypanel-mcp's get_service)
        db_password: database password (get via easypanel-mcp's get_service);
            never logged or written to disk anywhere
    """
    return await tools.backup_database_to_local(
        project_name, service_name, db_type, db_user, db_name, db_password or None
    )


@mcp.tool(
    name="copy_file_to_local",
    annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=False),
)
async def copy_file_to_local(
    project_name: str,
    service_name: str,
    remote_path: str,
) -> dict:
    """
    Copy an arbitrary file (e.g. a SQLite database) out of a live
    Easypanel-managed container straight to local disk, gzip-compressed,
    binary-safe. Use this instead of run_command for binary files --
    run_command's stdout capture decodes as text and will corrupt them. Saves
    under 08-SCRIPTS -BKPs-en-SERVERS-CLIENTES/10-BACKUPS/<client>/<date>_<service>-<file>-backup/outputs/.
    Never staged on the remote server.

    REQUIRES EXPLICIT USER APPROVAL BEFORE EVERY CALL, per docs/OPERACIONES_08.md.

    Args:
        project_name: Easypanel project name
        service_name: Easypanel service name (used to resolve the live container)
        remote_path: absolute path of the file inside the container
    """
    return await tools.copy_file_to_local(project_name, service_name, remote_path)


def main() -> None:
    logger.info("Starting infra-ssh-mcp for %s (%s)", config.client_label, config.host)
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
