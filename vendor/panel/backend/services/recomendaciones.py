"""
Recomendaciones y recordatorios de trabajo: lo que el panel le sugiere a la persona
para que el día a día no dependa de acordarse de todo.

Todo se calcula en el momento a partir de lo que ya hay en el equipo (tareas,
ejecuciones, respaldos, conectores): no se inventa nada ni se consulta afuera.
Las credenciales se miran solo para saber si están vacías; su valor nunca sale
de acá.
"""
import time
from datetime import datetime

from config import DATA_ROOT, MCP_REGISTRY, STACK_CONFIG_DIR
from db import ajuste, db_session
from services.scheduler import parse_fecha


def _item(tipo, nivel, titulo, detalle, accion=None, clave=None):
    return {"tipo": tipo, "nivel": nivel, "titulo": titulo, "detalle": detalle, "accion": accion,
            "clave": clave or titulo}


def _ultimo_respaldo() -> float | None:
    carpeta = DATA_ROOT / "05-OPERACIONES" / "backups" / "stack"
    archivos = list(carpeta.glob("stack-*.tar.gz")) if carpeta.exists() else []
    return max((f.stat().st_mtime for f in archivos), default=None)


def _conectores_sin_clave() -> list[str]:
    secretos = STACK_CONFIG_DIR / "secrets"
    faltan = []
    if not MCP_REGISTRY.exists():
        return faltan
    for raw in MCP_REGISTRY.read_text(encoding="utf-8").splitlines():
        servidor = raw.split("\t")[0]
        env = secretos / f"{servidor}.env"
        if not env.exists():
            continue
        for linea in env.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" in linea and not linea.strip().startswith("#") and linea.split("=", 1)[1].strip().strip('"') == "":
                faltan.append(servidor)
                break
    return faltan


def calcular(autostart_activo: bool) -> list[dict]:
    ahora = datetime.now()
    items = []
    with db_session() as conn:
        tareas = [dict(r) for r in conn.execute("SELECT * FROM tasks WHERE estado NOT IN ('hecho','descartada')")]
        para_revisar = [dict(r) for r in conn.execute(
            "SELECT * FROM runs WHERE tipo = 'tarea' AND revisado = 0 AND estado IN ('ok','error') ORDER BY id DESC LIMIT 20")]
        ultimo_doctor = conn.execute(
            "SELECT fin, estado FROM runs WHERE tipo = 'mantenimiento' AND accion LIKE 'revisar%' AND estado IN ('ok','error') "
            "ORDER BY id DESC LIMIT 1").fetchone()
        recordatorios = [dict(r) for r in conn.execute("SELECT * FROM recordatorios WHERE hecho = 0")]

    # --- recordatorios ---------------------------------------------------------
    for r in para_revisar:
        items.append(_item("recordatorio", "accion" if r["estado"] == "ok" else "alerta",
                           f"Revisá el resultado de «{r['titulo']}»",
                           "Terminó bien y espera tu revisión." if r["estado"] == "ok" else "Terminó con errores: mirá qué pasó.",
                           {"tipo": "ejecucion", "id": r["id"]}, f"run-{r['id']}"))
    for t in tareas:
        cuando = parse_fecha(t.get("programada_para"))
        if cuando and cuando <= ahora and t["estado"] == "pendiente" and t.get("ejecucion") != "auto":
            items.append(_item("recordatorio", "alerta", f"«{t['titulo']}» ya venció",
                               f"Estaba para el {cuando.strftime('%d/%m %H:%M')}. Lanzala o marcala hecha.",
                               {"tipo": "tarea", "id": t["id"]}, f"tarea-{t['id']}"))
        if t["estado"] == "listo_para_revision" and not any(r["tarea_id"] == t["id"] for r in para_revisar):
            items.append(_item("recordatorio", "accion", f"«{t['titulo']}» está lista para revisar", "",
                               {"tipo": "tarea", "id": t["id"]}, f"lista-{t['id']}"))
    for r in recordatorios:
        cuando = parse_fecha(r.get("cuando"))
        if not cuando or cuando <= ahora:
            items.append(_item("recordatorio", "accion", r["texto"],
                               cuando.strftime("Para el %d/%m %H:%M") if cuando else "Recordatorio tuyo",
                               {"tipo": "recordatorio", "id": r["id"]}, f"rec-{r['id']}"))

    # --- recomendaciones -------------------------------------------------------
    ult = _ultimo_respaldo()
    if ult is None:
        items.append(_item("recomendacion", "sugerencia", "Hacé tu primer respaldo",
                           "Guarda agentes, memoria y configuración en un archivo comprimido.",
                           {"tipo": "mantenimiento", "accion": "respaldo"}))
    elif time.time() - ult > 7 * 86400:
        dias = int((time.time() - ult) / 86400)
        items.append(_item("recomendacion", "sugerencia", "Toca hacer un respaldo",
                           f"El último fue hace {dias} días.", {"tipo": "mantenimiento", "accion": "respaldo"}))

    if not ultimo_doctor:
        items.append(_item("recomendacion", "sugerencia", "Revisá que todo esté bien",
                           "Un diagnóstico completo: disco, agentes, conectores y credenciales.",
                           {"tipo": "mantenimiento", "accion": "revisar"}))
    elif ultimo_doctor["estado"] == "error":
        items.append(_item("recomendacion", "alerta", "El último diagnóstico encontró problemas",
                           "Abrilo para ver qué conector o qué parte falla.",
                           {"tipo": "mantenimiento", "accion": "revisar"}))
    else:
        cuando = parse_fecha(ultimo_doctor["fin"])
        if cuando and (ahora - cuando).days >= 7:
            items.append(_item("recomendacion", "sugerencia", "Hace una semana que no revisás el estado",
                               "Conviene un diagnóstico semanal.", {"tipo": "mantenimiento", "accion": "revisar"}))

    for servidor in _conectores_sin_clave():
        items.append(_item("recomendacion", "sugerencia", f"Completá las claves de {servidor}",
                           "El conector está instalado pero le falta una credencial: sin ella no funciona.",
                           {"tipo": "ir", "a": "/mantenimiento"}, f"clave-{servidor}"))

    pendientes = ajuste("actualizaciones_pendientes", "0")
    if pendientes.isdigit() and int(pendientes) > 0:
        items.append(_item("recomendacion", "sugerencia", "Hay una versión nueva de Ideas Box",
                           f"{pendientes} cambio(s) nuevos publicados.", {"tipo": "mantenimiento", "accion": "actualizar"}))

    programadas_auto = [t for t in tareas if t.get("ejecucion") == "auto" and t.get("programada_para")]
    if programadas_auto and not autostart_activo:
        items.append(_item("recomendacion", "sugerencia", "Activá el arranque automático del panel",
                           "Tenés tareas que se ejecutan solas, y solo corren si el panel está abierto.",
                           {"tipo": "ir", "a": "/mantenimiento"}))
    if not any(t.get("programada_para") for t in tareas):
        items.append(_item("recomendacion", "sugerencia", "Programá tu primera rutina",
                           "Por ejemplo: un resumen semanal de pendientes con clientes, o un control mensual de servidores.",
                           {"tipo": "ir", "a": "/tareas?nueva=1"}))

    orden = {"alerta": 0, "accion": 1, "sugerencia": 2}
    items.sort(key=lambda i: orden.get(i["nivel"], 3))
    return items


