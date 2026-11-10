"""Lógica de las herramientas, separada del servidor MCP para poder probarla sola."""
import time
from typing import Any, Dict, List

from . import store
from .client import UNTRUSTED_NOTE, Disruptia, fail

POLL_SECONDS = 5
POLL_BUDGET_SECONDS = 25

_SERVICE_KEYS = ("id", "nombre", "tipo_label", "estado", "plan_nombre", "fecha_inicio", "fecha_fin",
                 "gateway_url", "monto_acordado", "tool_pending_assignment", "tool_paused")
_CATALOG_KEYS = ("code", "name", "category", "price", "cadence", "description", "is_acquired", "trial_days")
_TICKET_KEYS = ("id", "numero", "titulo", "estado", "prioridad", "categoria", "producto_relacionado",
                "fecha_creacion", "fecha_actualizacion")


def _pick(items: Any, keys) -> List[Dict[str, Any]]:
    return [{k: it.get(k) for k in keys if k in it} for it in (items or []) if isinstance(it, dict)]


def estado(api: Disruptia) -> Dict[str, Any]:
    if not store.connection_key():
        pending = store.load_pending()
        return {"success": True, "connected": False,
                "pending_code": pending.get("user_code"),
                "message": "No conectado todavía. Usá disruptia_conectar."}
    r = api.request("GET", "/api/my/ideasbox/status")
    if r.get("success") is False:
        return r
    return {"success": True, "connected": True, "eligible": r.get("eligible"),
            "message": r.get("message"), "connections": r.get("connections", [])}


def conectar(api: Disruptia) -> Dict[str, Any]:
    r = api.device_start()
    if not r.get("success"):
        return r
    store.save_pending(store.base_url(), r["device_code"], r["user_code"])
    return {
        "success": True,
        "user_code": r["user_code"],
        "verification_url": r["verification_url"],
        "expires_in_seconds": r["expires_in"],
        "message": (f"Pedile al usuario que abra {r['verification_url']} con su sesión de DisruptIA e ingrese el "
                    f"código {r['user_code']}. Cuando lo apruebe, llamá a disruptia_conectar_confirmar."),
    }


def conectar_confirmar(api: Disruptia, sleep=time.sleep, budget: int = POLL_BUDGET_SECONDS) -> Dict[str, Any]:
    pending = store.load_pending()
    if not pending.get("device_code"):
        return fail("No hay una conexión en curso. Usá disruptia_conectar primero.")
    waited = 0
    while True:
        res = api.device_poll(pending["device_code"])
        state = res["state"]
        if state == "ok":
            store.save_connection(pending.get("url") or store.base_url(), res["connection_key"])
            store.clear_pending()
            return {"success": True, "connected": True, "message": "Listo: Ideas Box quedó conectado a tu cuenta de DisruptIA."}
        if state in ("expired", "invalid", "denied"):
            store.clear_pending()
            return fail(res.get("message") or "No se pudo conectar.", state=state)
        if state == "error":
            return fail(res["message"])
        if waited >= budget:
            return fail("Todavía no lo aprobaron. Cuando lo hagan, volvé a llamar a disruptia_conectar_confirmar.",
                        state="pending", user_code=pending.get("user_code"))
        sleep(POLL_SECONDS)
        waited += POLL_SECONDS


def desconectar() -> Dict[str, Any]:
    store.clear_connection()
    store.clear_pending()
    return {"success": True, "message": ("Ideas Box ya no está conectado en este equipo. Para cortar el acceso del todo, "
                                         "revocá la conexión desde tu panel de DisruptIA.")}


def mis_servicios(api: Disruptia) -> Dict[str, Any]:
    r = api.request("GET", "/api/my/services")
    if r.get("success") is False:
        return r
    return {"success": True, "services": _pick(r.get("services"), _SERVICE_KEYS)}


def tienda_listar(api: Disruptia) -> Dict[str, Any]:
    r = api.request("GET", "/api/my/store/catalog")
    if r.get("success") is False:
        return r
    return {"success": True, "catalog": _pick(r.get("catalog"), _CATALOG_KEYS), "nota": UNTRUSTED_NOTE}


def tienda_activar_prueba(api: Disruptia, codigo: str) -> Dict[str, Any]:
    codigo = (codigo or "").strip()
    if not codigo:
        return fail("Indicá el código del producto (lo ves en tienda_listar).")
    r = api.request("POST", "/api/my/ideasbox/store/activate-trial", json={"saas_code": codigo})
    return r


def tickets_listar(api: Disruptia) -> Dict[str, Any]:
    r = api.request("GET", "/api/my/tickets")
    if r.get("success") is False:
        return r
    return {"success": True, "tickets": _pick(r.get("tickets"), _TICKET_KEYS), "nota": UNTRUSTED_NOTE}


def ticket_ver(api: Disruptia, ticket_id: str) -> Dict[str, Any]:
    ticket_id = (ticket_id or "").strip()
    if not ticket_id:
        return fail("Indicá el id del ticket.")
    t = api.request("GET", f"/api/my/tickets/{ticket_id}")
    if t.get("success") is False:
        return t
    m = api.request("GET", f"/api/my/tickets/{ticket_id}/messages")
    messages = [] if m.get("success") is False else [
        {k: x.get(k) for k in ("mensaje", "fecha_creacion", "autor", "usuario_nombre", "es_staff", "adjuntos") if k in x}
        for x in (m.get("messages") or []) if isinstance(x, dict)]
    return {"success": True, "ticket": t.get("ticket", t), "messages": messages, "nota": UNTRUSTED_NOTE}


def ticket_crear(api: Disruptia, titulo: str, descripcion: str, categoria: str = "general",
                 prioridad: str = "media", producto: str = "") -> Dict[str, Any]:
    if not (titulo or "").strip() or not (descripcion or "").strip():
        return fail("El título y la descripción son obligatorios.")
    body = {"titulo": titulo.strip(), "descripcion": descripcion.strip(),
            "categoria": categoria, "prioridad": prioridad, "producto_saas": producto}
    r = api.request("POST", "/api/my/tickets", json=body)
    if r.get("success") is False:
        return r
    reserved = r.get("credits_reserved") or 0
    if reserved:
        r["aviso_creditos"] = f"Este ticket reservó {reserved} crédito(s) de soporte."
    return r


def ticket_responder(api: Disruptia, ticket_id: str, mensaje: str) -> Dict[str, Any]:
    if not (ticket_id or "").strip() or not (mensaje or "").strip():
        return fail("Indicá el id del ticket y el mensaje.")
    return api.request("POST", f"/api/my/tickets/{ticket_id.strip()}/messages", json={"mensaje": mensaje.strip()})
