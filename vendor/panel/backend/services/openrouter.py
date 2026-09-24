"""Cliente OpenRouter compartido -- usado por chat.py (interpretación) y
execution.py (redacción real de contenido). La credencial es opcional: sin
OPENROUTER_API_KEY el panel funciona igual, solo se apagan esas dos funciones."""
import json
import urllib.error
import urllib.request

from fastapi import HTTPException

from config import PANEL_ENV_PATH
from env import load_env


def call_openrouter(system_prompt: str, messages: list[dict], temperature: float = 0.3) -> str:
    """messages: lista de {"role": "user"|"assistant", "content": str}, sin el system."""
    env = load_env(PANEL_ENV_PATH)
    api_key = env.get("OPENROUTER_API_KEY")
    if not api_key:
        raise HTTPException(503, f"falta OPENROUTER_API_KEY -- configurar en {PANEL_ENV_PATH}")
    model = env.get("OPENROUTER_MODEL", "openai/gpt-4o-mini")

    body = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": system_prompt}, *messages],
        "temperature": temperature,
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise HTTPException(502, f"OpenRouter devolvió {e.code}: {e.read().decode('utf-8', 'replace')[:300]}")
    except urllib.error.URLError as e:
        raise HTTPException(502, f"error de red hacia OpenRouter: {e}")

    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError):
        raise HTTPException(502, f"respuesta inesperada de OpenRouter: {json.dumps(data)[:300]}")
