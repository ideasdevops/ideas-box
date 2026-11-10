"""Dónde se guarda la conexión. Nada de esto va a ~/.claude.json ni al repo.

La clave de la conexión la entrega DisruptIA una sola vez, cuando el cliente aprueba
el código en su panel. Queda en un archivo con permisos 600, igual que los .env de
los demás conectores de Ideas Box.
"""
import json
import os
import stat
from pathlib import Path
from typing import Any, Dict, Optional

DEFAULT_URL = "https://plataforma.disruptia.app"


def secrets_dir() -> Path:
    explicit = os.getenv("IDEASBOX_SECRETS_DIR")
    if explicit:
        return Path(explicit).expanduser()
    return Path(os.getenv("IDEASBOX_CONFIG_DIR") or "~/.config/ideasbox").expanduser() / "secrets"


def _file(name: str) -> Path:
    return secrets_dir() / name


def _read(name: str) -> Dict[str, Any]:
    try:
        return json.loads(_file(name).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _write(name: str, data: Dict[str, Any]) -> None:
    path = _file(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    # Se crea ya con permisos 600: la clave nunca existe en disco con permisos más abiertos.
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, stat.S_IRUSR | stat.S_IWUSR)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    os.replace(tmp, path)


def base_url() -> str:
    url = os.getenv("DISRUPTIA_URL") or _read("disruptia.json").get("url") or DEFAULT_URL
    return url.rstrip("/")


def connection_key() -> Optional[str]:
    return os.getenv("DISRUPTIA_CONNECTION_KEY") or _read("disruptia.json").get("connection_key") or None


def save_connection(url: str, key: str) -> None:
    _write("disruptia.json", {"url": url.rstrip("/"), "connection_key": key})


def clear_connection() -> None:
    try:
        _file("disruptia.json").unlink()
    except OSError:
        pass


def save_pending(url: str, device_code: str, user_code: str) -> None:
    _write("disruptia-pending.json", {"url": url.rstrip("/"), "device_code": device_code, "user_code": user_code})


def load_pending() -> Dict[str, Any]:
    return _read("disruptia-pending.json")


def clear_pending() -> None:
    try:
        _file("disruptia-pending.json").unlink()
    except OSError:
        pass
