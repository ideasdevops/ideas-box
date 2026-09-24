"""Loader compartido de los .env del stack (fuera del repo y de la raíz de
datos) -- usado por los servicios que necesitan credenciales, para no duplicar
el parser."""
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=4)
def load_env(path: Path) -> dict:
    if not path.exists():
        return {}
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env
