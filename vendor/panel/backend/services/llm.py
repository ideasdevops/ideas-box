"""
Modelo para las funciones cortas del panel (convertir un pedido en una tarea).

Por defecto usa Claude Code con la cuenta que ya tiene el equipo: no hace falta
ninguna clave extra. Si hay OPENROUTER_API_KEY en panel.env, se usa OpenRouter
(como antes). Es una sola respuesta, sin herramientas: no ejecuta nada.
"""
import json
import subprocess

from fastapi import HTTPException

from config import DATA_ROOT, PANEL_ENV_PATH
from env import load_env
from services.runner import claude_bin


def call_llm(system_prompt: str, messages: list[dict], temperature: float = 0.3) -> str:
    if load_env(PANEL_ENV_PATH).get("OPENROUTER_API_KEY"):
        from services.openrouter import call_openrouter  # noqa: PLC0415
        return call_openrouter(system_prompt, messages, temperature)

    claude = claude_bin()
    if not claude:
        raise HTTPException(503, "No encuentro Claude Code en este equipo.")
    conversacion = "\n\n".join(
        f"{'Persona' if m['role'] == 'user' else 'Vos'}: {m['content']}" for m in messages
    )
    prompt = f"Conversación hasta ahora:\n\n{conversacion}\n\nRespondé el último mensaje de la persona."
    try:
        r = subprocess.run(
            [claude, "-p", prompt, "--output-format", "json", "--append-system-prompt", system_prompt,
             "--permission-mode", "dontAsk", "--permission-prompts", "none", "--max-turns", "2"],
            cwd=str(DATA_ROOT), capture_output=True, text=True, timeout=180, stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Claude tardó demasiado en responder.")
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        raise HTTPException(502, f"Respuesta inesperada de Claude Code: {(r.stdout or r.stderr)[:300]}")
    if data.get("is_error"):
        raise HTTPException(502, f"Claude Code no pudo responder: {str(data.get('result'))[:300]}")
    return data.get("result") or ""
