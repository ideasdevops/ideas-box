"""
Tool implementations for the infra SSH MCP server.

Read-only tools (docker_ps, docker_logs, docker_stats, system_info) are meant
to run freely for diagnostics. run_command and backup_database_to_local are
gated by agent policy (written in the agents' own instructions, not enforced
in code) -- they always require explicit user approval before use.
"""

from __future__ import annotations

import logging
import os
import re
import shlex
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from . import ssh_client
from .config import config

logger = logging.getLogger(__name__)

# Raíz donde se depositan los backups traídos de los servidores.
# La define el instalador del stack (variable de entorno INFRA_BACKUP_ROOT);
# si no está, cae a una carpeta del home para no escribir en rutas ajenas.
BACKUP_ROOT = Path(
    os.environ.get("INFRA_BACKUP_ROOT")
    or (Path.home() / "backups-servidores")
)

_SLUG_RE = re.compile(r"[^a-zA-Z0-9._-]+")


def _slug(text: str) -> str:
    return _SLUG_RE.sub("-", text).strip("-")


async def docker_ps() -> dict[str, Any]:
    """List running/stopped containers on the server."""
    result = await ssh_client.run(
        "docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.RunningFor}}'"
    )
    containers = []
    for line in result.stdout.strip().splitlines():
        parts = line.split("\t")
        if len(parts) == 4:
            containers.append(
                {"name": parts[0], "image": parts[1], "status": parts[2], "running_for": parts[3]}
            )
    return {"success": result.ok, "containers": containers, "stderr": result.stderr if not result.ok else None}


async def _find_container(project_name: str, service_name: str) -> tuple[str | None, list[str]]:
    """
    Resolve the current live container name for a project/service.

    Easypanel (Docker Swarm) names containers as
    "<projectName>_<serviceName>.<replica>.<task-hash>" -- the replica/hash
    suffix changes on every redeploy, so it can't be hardcoded or cached long
    term; always resolve it fresh right before use.
    """
    result = await ssh_client.run("docker ps --format '{{.Names}}'")
    all_names = [n for n in result.stdout.strip().splitlines() if n]
    prefix = f"{project_name}_{service_name}."
    matches = [n for n in all_names if n.startswith(prefix)]
    return (matches[0] if matches else None), all_names


async def docker_logs(container_name: str, lines: int = 100) -> dict[str, Any]:
    """
    Get recent logs from a container. Accepts either an exact container name
    or a "project_service" prefix (resolves the live replica automatically).
    """
    target = container_name
    if "." not in container_name:
        found, all_names = await _find_container(*container_name.split("_", 1)) if "_" in container_name else (None, [])
        if found:
            target = found
        else:
            return {
                "success": False,
                "error": f"No container found matching '{container_name}'. Use docker_ps to see live container names.",
            }
    result = await ssh_client.run(f"docker logs --tail {int(lines)} {target} 2>&1")
    return {"success": result.ok, "container": target, "logs": result.stdout, "stderr": result.stderr if not result.ok else None}


async def docker_stats() -> dict[str, Any]:
    """Snapshot of CPU/memory usage per running container (no streaming)."""
    result = await ssh_client.run(
        "docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'"
    )
    stats = []
    for line in result.stdout.strip().splitlines():
        parts = line.split("\t")
        if len(parts) == 4:
            stats.append({"name": parts[0], "cpu": parts[1], "mem_usage": parts[2], "mem_percent": parts[3]})
    return {"success": result.ok, "stats": stats, "stderr": result.stderr if not result.ok else None}


async def system_info() -> dict[str, Any]:
    """Host-level uptime, disk and memory usage."""
    uptime = await ssh_client.run("uptime")
    disk = await ssh_client.run("df -h /")
    mem = await ssh_client.run("free -h")
    return {
        "success": uptime.ok and disk.ok and mem.ok,
        "uptime": uptime.stdout.strip(),
        "disk": disk.stdout.strip(),
        "memory": mem.stdout.strip(),
    }


async def run_command(command: str, timeout: float = 60.0) -> dict[str, Any]:
    """
    Run an arbitrary shell command on the server. GATED: agent policy requires
    explicit user approval before every call to this tool -- it can mutate or
    destroy anything on the host.
    """
    result = await ssh_client.run(command, timeout=timeout)
    return {
        "success": result.ok,
        "exit_status": result.exit_status,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


async def backup_database_to_local(
    project_name: str,
    service_name: str,
    db_type: str,
    db_user: str,
    db_name: str,
    db_password: str | None = None,
) -> dict[str, Any]:
    """
    Dump a database running inside an Easypanel-managed container and stream
    it directly to local disk (never staged on the remote server). GATED:
    agent policy requires explicit user approval before every call.

    db_type: "postgres" or "mysql"/"mariadb". db_user/db_name/db_password come
    from the corresponding easypanel-mcp get_service call (this tool has no
    Easypanel API access of its own, by design -- keeps the two MCPs decoupled).
    """
    container, all_names = await _find_container(project_name, service_name)
    if not container:
        return {
            "success": False,
            "error": (
                f"No running container found for {project_name}/{service_name}. "
                f"Live containers on this host: {all_names}"
            ),
        }

    if db_type == "postgres":
        pwd_prefix = f"-e PGPASSWORD={db_password} " if db_password else ""
        inner_cmd = f"docker exec {pwd_prefix}{container} pg_dump -U {db_user} {db_name} | gzip"
    elif db_type == "mysql":
        pwd_prefix = f"-e MYSQL_PWD={db_password} " if db_password else ""
        inner_cmd = f"docker exec {pwd_prefix}{container} mysqldump -u{db_user} {db_name} | gzip"
    elif db_type == "mariadb":
        # mariadb:11+ images ship mariadb-dump, not the mysqldump compat
        # symlink -- confirmed empirically 2026-09-02 (every mariadb backup
        # was silently reporting success:true with a gzipped "executable
        # file not found" error instead of a real dump, see the pipefail
        # fix below for why that went undetected).
        pwd_prefix = f"-e MYSQL_PWD={db_password} " if db_password else ""
        inner_cmd = f"docker exec {pwd_prefix}{container} mariadb-dump -u{db_user} {db_name} | gzip"
    else:
        return {"success": False, "error": f"Unsupported db_type '{db_type}' (expected postgres/mysql/mariadb)"}

    # Without pipefail, a failed `docker exec` (nonzero exit) is masked by
    # `gzip` succeeding on whatever stray output it received -- the pipeline's
    # exit status was silently coming from gzip, not the dump command, so a
    # broken dump could still report success:true. Force bash + pipefail so
    # the real failure propagates.
    dump_cmd = f"bash -c {shlex.quote('set -o pipefail; ' + inner_cmd)}"

    now = datetime.now(timezone.utc)
    date_slug = now.strftime("%Y-%m-%d")
    ts_slug = now.strftime("%Y%m%dT%H%M%SZ")
    op_slug = _slug(f"{date_slug}_{service_name}-backup")
    op_dir = BACKUP_ROOT / _slug(config.client_label) / op_slug
    outputs_dir = op_dir / "outputs"
    outputs_dir.mkdir(parents=True, exist_ok=True)

    filename = f"{_slug(service_name)}_{ts_slug}.sql.gz"
    local_path = outputs_dir / filename

    exit_status, bytes_written, stderr_text = await ssh_client.run_streaming_to_file(
        dump_cmd, str(local_path)
    )

    success = exit_status == 0 and bytes_written > 0
    if not success and local_path.exists() and bytes_written == 0:
        local_path.unlink()

    _write_operation_log(
        op_dir=op_dir,
        client_label=config.client_label,
        host=config.host,
        project_name=project_name,
        service_name=service_name,
        db_type=db_type,
        success=success,
        bytes_written=bytes_written,
        output_path=local_path if success else None,
        stderr_text=stderr_text if not success else "",
        timestamp=now,
    )

    return {
        "success": success,
        "container": container,
        "output_path": str(local_path) if success else None,
        "bytes_written": bytes_written,
        "operation_dir": str(op_dir),
        "stderr": stderr_text if not success else None,
    }


async def copy_file_to_local(
    project_name: str,
    service_name: str,
    remote_path: str,
) -> dict[str, Any]:
    """
    Copy an arbitrary file out of a live Easypanel-managed container (e.g. a
    SQLite database file not covered by backup_database_to_local, which only
    handles postgres/mysql/mariadb) straight to local disk, gzip-compressed,
    binary-safe (streamed, never decoded as text -- unlike run_command's
    stdout capture, which would corrupt binary content). Never staged on the
    remote server. GATED: agent policy requires explicit user approval
    before every call.
    """
    container, all_names = await _find_container(project_name, service_name)
    if not container:
        return {
            "success": False,
            "error": (
                f"No running container found for {project_name}/{service_name}. "
                f"Live containers on this host: {all_names}"
            ),
        }

    inner_cmd = f"docker exec {container} cat {shlex.quote(remote_path)} | gzip"
    dump_cmd = f"bash -c {shlex.quote('set -o pipefail; ' + inner_cmd)}"

    now = datetime.now(timezone.utc)
    date_slug = now.strftime("%Y-%m-%d")
    ts_slug = now.strftime("%Y%m%dT%H%M%SZ")
    file_label = Path(remote_path).name or service_name
    op_slug = _slug(f"{date_slug}_{service_name}-{file_label}-backup")
    op_dir = BACKUP_ROOT / _slug(config.client_label) / op_slug
    outputs_dir = op_dir / "outputs"
    outputs_dir.mkdir(parents=True, exist_ok=True)

    filename = f"{_slug(file_label)}_{ts_slug}.gz"
    local_path = outputs_dir / filename

    exit_status, bytes_written, stderr_text = await ssh_client.run_streaming_to_file(
        dump_cmd, str(local_path)
    )

    success = exit_status == 0 and bytes_written > 0
    if not success and local_path.exists() and bytes_written == 0:
        local_path.unlink()

    _write_operation_log(
        op_dir=op_dir,
        client_label=config.client_label,
        host=config.host,
        project_name=project_name,
        service_name=service_name,
        db_type=f"file ({remote_path})",
        success=success,
        bytes_written=bytes_written,
        output_path=local_path if success else None,
        stderr_text=stderr_text if not success else "",
        timestamp=now,
        agent_tool="copy_file_to_local",
        action_desc=(
            f"Copia de `{remote_path}` vía `docker exec ... cat | gzip` sobre el "
            f"contenedor vivo de {project_name}/{service_name}, transferida directo a "
            f"disco local (sin quedar en el servidor remoto)."
        ),
    )

    return {
        "success": success,
        "container": container,
        "output_path": str(local_path) if success else None,
        "bytes_written": bytes_written,
        "operation_dir": str(op_dir),
        "stderr": stderr_text if not success else None,
    }


def _write_operation_log(
    *,
    op_dir: Path,
    client_label: str,
    host: str,
    project_name: str,
    service_name: str,
    db_type: str,
    success: bool,
    bytes_written: int,
    output_path: Path | None,
    stderr_text: str,
    timestamp: datetime,
    agent_tool: str = "backup_database_to_local",
    action_desc: str | None = None,
) -> None:
    """
    Write OPERATION.md per docs/OPERACIONES_08.md's backup exception: metadata
    only, never credentials. The actual dump lives in outputs/, referenced by
    path/size, not duplicated into this file.
    """
    status = "cerrada" if success else "bloqueada"
    size_mb = f"{bytes_written / (1024 * 1024):.2f} MB" if bytes_written else "0 MB"
    if action_desc is None:
        action_desc = (
            f"Dump de {db_type} vía `docker exec` + `pg_dump`/`mysqldump`/`mariadb-dump` "
            f"sobre el contenedor vivo de {project_name}/{service_name}, transferido "
            f"directo a disco local (sin quedar en el servidor remoto)."
        )
    content = f"""# Operación

- Cliente: {client_label}
- Tipo: backup
- Fecha: {timestamp.isoformat()}
- Agente responsable: infra-ssh-mcp ({agent_tool})
- Solicitud y alcance: backup de {db_type} para {project_name}/{service_name} en {host}, pedido explícitamente por el usuario en sesión de chat.
- Aprobación: solicitado explícitamente por el usuario (excepción de docs/OPERACIONES_08.md para dumps de base de datos).
- Estado: {status}

## Acciones realizadas
- {action_desc}

## Resultado y ubicación de outputs
{f"- Archivo: `{output_path}` ({size_mb})" if output_path else "- Falló, sin archivo generado."}

## Evidencia saneada
- Tamaño del dump: {size_mb}
{f"- stderr: {stderr_text.strip()[:500]}" if stderr_text.strip() else ""}

## Riesgos, reversión y próximo paso
- No se guardaron credenciales de la base de datos en esta bitácora.
- Verificar integridad del dump (`gunzip -t`) antes de considerarlo restaurable.
"""
    (op_dir / "OPERATION.md").write_text(content, encoding="utf-8")
