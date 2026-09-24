"""
Aviso de "tarea lista para revisar".

El canal es opcional y configurable en `secrets/panel.env`: sin configurar, el
panel funciona igual y el trabajo queda en el tablero esperando revisión.

Canales soportados:

  · webhook    POST JSON a NOTIFY_WEBHOOK_URL. Sirve para Slack, Discord, n8n
               o cualquier cosa que acepte un POST.
  · evolution  WhatsApp por Evolution API (NOTIFY_WHATSAPP_NUMBER).

Nunca bloquea: si el aviso falla, el contenido ya generado no se pierde. Avisar
es secundario; perder el trabajo, no.
"""
import json
import logging
import urllib.error
import urllib.request

from config import EMPRESA_NOMBRE, PANEL_ENV_PATH
from env import load_env

logger = logging.getLogger("panel.notify")

_UA = "ideasbox-panel"
_TIMEOUT = 15


def _cuerpo_del_aviso(task: dict) -> str:
    resultado = (task.get("resultado_ejecucion") or "").strip()
    if len(resultado) > 1500:
        resultado = resultado[:1500] + "..."
    revisar = (
        "sí — marcada para publicar pronto"
        if task.get("auto_publicar")
        else "no — solo revisar"
    )
    return "\n".join([
        f"[{EMPRESA_NOMBRE}] Tarea lista para revisar",
        f"Título: {task.get('titulo', 'n/a')}",
        f"Agente: {task.get('agente_sugerido', 'n/a')}",
        f"Pedido de publicación: {revisar}",
        "Resultado:",
        resultado or "(sin contenido generado)",
    ])


def _post(url: str, headers: dict, payload: dict) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": _UA, **headers},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            cuerpo = resp.read().decode("utf-8", "replace")
        try:
            return {"ok": True, "data": json.loads(cuerpo)}
        except json.JSONDecodeError:
            return {"ok": True, "data": cuerpo[:300]}
    except urllib.error.HTTPError as e:
        detalle = e.read().decode("utf-8", "replace")[:300]
        logger.warning("aviso: HTTP %s — %s", e.code, detalle)
        return {"ok": False, "reason": "http_error", "status": e.code}
    except urllib.error.URLError as e:
        logger.warning("aviso: error de red — %s", e)
        return {"ok": False, "reason": "network_error"}


def send_task_ready_alert(task: dict) -> dict:
    env = load_env(PANEL_ENV_PATH)
    texto = _cuerpo_del_aviso(task)

    canal = env.get("NOTIFY_CHANNEL", "").strip().lower()
    if not canal:
        # Sin canal explícito: se usa el que esté configurado.
        if env.get("NOTIFY_WEBHOOK_URL"):
            canal = "webhook"
        elif env.get("EVOLUTION_API_URL"):
            canal = "evolution"
        else:
            canal = "none"

    if canal == "none":
        logger.info("aviso: sin canal configurado, la tarea queda en el tablero")
        return {"ok": False, "reason": "not_configured"}

    if canal == "webhook":
        url = env.get("NOTIFY_WEBHOOK_URL")
        if not url:
            return {"ok": False, "reason": "not_configured"}
        return _post(url, {}, {"text": texto, "tarea": task.get("id")})

    if canal == "evolution":
        url = env.get("EVOLUTION_API_URL")
        api_key = env.get("EVOLUTION_API_KEY")
        instancia = env.get("EVOLUTION_INSTANCE")
        numero = env.get("NOTIFY_WHATSAPP_NUMBER")
        if not all([url, api_key, instancia, numero]):
            logger.warning("aviso: faltan datos de Evolution API en %s", PANEL_ENV_PATH)
            return {"ok": False, "reason": "not_configured"}
        return _post(
            f"{url.rstrip('/')}/message/sendText/{instancia}",
            {"apikey": api_key},
            {"number": numero, "text": texto},
        )

    logger.warning("aviso: canal desconocido '%s'", canal)
    return {"ok": False, "reason": "unknown_channel"}
