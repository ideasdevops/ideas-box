"""
Planificador: dispara las tareas programadas mientras el panel está abierto.

Cada tarea programada se marca de una de dos formas (columna `ejecucion`):

  · auto    «ejecutar sola»: a su hora entra en la fila de tareas y el resultado
            queda para revisar. Si es recurrente, se reprograma para la próxima
            fecha en el mismo momento en que se encola.
  · manual  «solo recordarme»: a su hora queda como recordatorio vencido en el
            panel; la persona la lanza (o la completa) cuando quiera.

Si el panel estuvo cerrado y se pasaron varias ocurrencias, se ejecuta una sola
vez al volver (no una por cada ocurrencia perdida) y la próxima fecha se corre al
futuro. Las horas son locales, sin zona: las escribe el navegador del mismo equipo.
"""
import logging
import subprocess
import threading
import time
from datetime import datetime, timedelta

from db import db_session, guardar_ajuste
from services.runner import runner, _stack_src

logger = logging.getLogger("panel.scheduler")

FORMATO = "%Y-%m-%dT%H:%M"


def siguiente(base: datetime, recurrencia: str) -> datetime:
    if recurrencia == "diaria":
        return base + timedelta(days=1)
    if recurrencia == "semanal":
        return base + timedelta(weeks=1)
    if recurrencia == "mensual":
        month = base.month % 12 + 1
        year = base.year + (1 if base.month == 12 else 0)
        for day in range(base.day, 0, -1):
            try:
                return base.replace(year=year, month=month, day=day)
            except ValueError:
                continue
    return base


def parse_fecha(valor: str | None) -> datetime | None:
    if not valor:
        return None
    for fmt in (FORMATO, "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(valor[:19], fmt)
        except ValueError:
            continue
    return None


def prompt_de_tarea(t: dict) -> str:
    partes = [f"Tarea del panel: {t['titulo']}"]
    if t.get("descripcion"):
        partes.append(t["descripcion"])
    if t.get("server_objetivo"):
        partes.append(f"Servidor involucrado: {t['server_objetivo']}.")
    partes.append(
        "Trabajá la tarea de punta a punta con lo que tenés permitido y terminá con un resumen claro: "
        "qué hiciste, qué dejaste listo (con la ruta de cada archivo) y qué queda pendiente de una persona. "
        "Si algo necesita aprobación (publicar, enviar, desplegar, correr un comando), no lo intentes de otra "
        "forma: dejalo anotado como pendiente."
    )
    return "\n\n".join(partes)


def lanzar_tarea(t: dict, origen: str = "manual") -> int:
    return runner().encolar_agente(
        tipo="tarea", titulo=t["titulo"], prompt=prompt_de_tarea(t), agente=t.get("agente_sugerido") or "",
        modo=t.get("modo") or "carpeta", tarea_id=t["id"], origen=origen,
    )


def _revisar_vencidas() -> None:
    ahora = datetime.now()
    with db_session() as conn:
        tareas = [dict(r) for r in conn.execute(
            "SELECT * FROM tasks WHERE estado = 'pendiente' AND programada_para IS NOT NULL AND programada_para != ''"
        ).fetchall()]
        activas = {r[0] for r in conn.execute(
            "SELECT tarea_id FROM runs WHERE estado IN ('en_cola','corriendo') AND tarea_id IS NOT NULL"
        ).fetchall()}
    for t in tareas:
        cuando = parse_fecha(t["programada_para"])
        if not cuando or cuando > ahora:
            continue
        if t["ejecucion"] == "auto":
            if t["id"] in activas:
                continue
            lanzar_tarea(t, origen="programada")
            cambios = {"avisada": 0}
            if t["recurrencia"] != "ninguna":
                prox = cuando
                while prox <= ahora:
                    prox = siguiente(prox, t["recurrencia"])
                cambios["programada_para"] = prox.strftime(FORMATO)
                cambios["proximo_vencimiento"] = prox.date().isoformat()
            else:
                cambios["estado"] = "en_progreso"
            sets = ", ".join(f"{k} = ?" for k in cambios)
            with db_session() as conn:
                conn.execute(f"UPDATE tasks SET {sets}, actualizada_en = datetime('now') WHERE id = ?", (*cambios.values(), t["id"]))
        elif not t["avisada"]:
            with db_session() as conn:
                conn.execute("UPDATE tasks SET avisada = 1 WHERE id = ?", (t["id"],))


def al_terminar_ejecucion(run: dict) -> None:
    """Refleja en la tarea el resultado de su ejecución y avisa si hay canal configurado."""
    if not run.get("tarea_id") or run["tipo"] != "tarea":
        return
    with db_session() as conn:
        row = conn.execute("SELECT * FROM tasks WHERE id = ?", (run["tarea_id"],)).fetchone()
        if not row:
            return
        t = dict(row)
        cambios = {"ultima_ejecucion_id": run["id"], "resultado_ejecucion": run.get("resultado") or ""}
        if t["recurrencia"] == "ninguna" and t["estado"] in ("pendiente", "en_progreso"):
            cambios["estado"] = "listo_para_revision" if run["estado"] == "ok" else "pendiente"
        sets = ", ".join(f"{k} = ?" for k in cambios)
        conn.execute(f"UPDATE tasks SET {sets}, actualizada_en = datetime('now') WHERE id = ?", (*cambios.values(), t["id"]))
        t.update(cambios)
    if run["estado"] == "ok":
        try:
            from services.notify import send_task_ready_alert  # noqa: PLC0415
            send_task_ready_alert(t)
        except Exception:  # noqa: BLE001 — avisar es secundario
            logger.exception("aviso de tarea lista")


def _chequear_actualizacion() -> None:
    """Una vez cada 12 h: ¿hay una versión nueva de Ideas Box en GitHub?"""
    src = _stack_src()
    if not src or not (src / ".git").exists():
        return
    try:
        subprocess.run(["git", "-C", str(src), "fetch", "--quiet", "origin", "main"], timeout=60,
                       capture_output=True, check=False)
        r = subprocess.run(["git", "-C", str(src), "rev-list", "--count", "HEAD..origin/main"], timeout=20,
                           capture_output=True, text=True, check=False)
        guardar_ajuste("actualizaciones_pendientes", (r.stdout or "0").strip() or "0")
        guardar_ajuste("actualizacion_chequeada", datetime.now().strftime(FORMATO))
    except (OSError, subprocess.SubprocessError):
        pass


def _bucle() -> None:
    ultimo_git = 0.0
    while True:
        try:
            _revisar_vencidas()
            if time.time() - ultimo_git > 12 * 3600:
                ultimo_git = time.time()
                threading.Thread(target=_chequear_actualizacion, daemon=True).start()
        except Exception:  # noqa: BLE001
            logger.exception("planificador")
        time.sleep(30)


def iniciar() -> None:
    runner().al_terminar.append(al_terminar_ejecucion)
    threading.Thread(target=_bucle, daemon=True, name="planificador").start()
