# Panel de Ideas Box

«El agente que acompaña y mejora el trabajo diario»: un tablero web local desde el
que se trabaja con los agentes sin necesidad de la terminal. Se instala con
`ideasbox panel install` y se abre con el ícono «Panel Ideas Box» o con
`ideasbox panel open`.

No se distribuye compilado: el instalador copia esta carpeta a
`~/.local/share/ideasbox/panel`, crea el entorno Python y compila la interfaz ahí.

## Secciones

| Sección | Qué hace |
|---|---|
| **Hoy** | Saludo, pedido rápido a un agente, lo que te espera (resultados para revisar, tareas vencidas, recordatorios), lo que está en marcha, lo próximo y recomendaciones |
| **Conversar** | Chat con cualquier agente. Cada conversación retoma la sesión anterior de Claude Code (`--resume`), así el agente recuerda |
| **Tareas** | El tablero: crear (a mano, desde plantilla o con palabras), ejecutar ahora, programar con fecha, hora y repetición, historial de ejecuciones |
| **Programación** | En curso, en la fila, próximas (14 días), vencidas, recordatorios y recomendaciones |
| **Actividad** | Solo mirar: lo que ejecuta el panel, en vivo, y las sesiones de Claude Code abiertas en la terminal (leídas de `~/.claude/projects`, nunca escritas) |
| **Agentes / Habilidades** | Por área, con búsqueda y ficha completa: herramientas por conector, habilidades que usa, instrucciones, origen de cada habilidad |
| **Servidores** | Derivados de los conectores de SSH y Easypanel instalados |
| **Mantenimiento** | Lo del menú de Ideas Box sin terminal: revisar, actualizar, respaldar, conectar herramientas (con sus claves), sumar habilidades, arranque automático, modelo y límite de pasos |

## Cómo ejecuta a los agentes

Con Claude Code en modo no interactivo (`claude -p --agent <agente>`), con la cuenta
que ya tiene el equipo: no hace falta ninguna clave extra. Tres filas independientes
(conversaciones, tareas, mantenimiento), de a una ejecución por fila, para que una
tarea larga no deje esperando a quien conversa. La salida queda en
`panel/runs/<id>.jsonl` y se muestra en vivo.

## La regla que no se negocia

Un agente del panel corre sin nadie que apruebe en el momento, así que **todo lo que
pediría aprobación se deniega solo** (`--permission-prompts none`). Cada tarea o
mensaje elige uno de dos modos:

- **Puede trabajar** (`acceptEdits`, con la raíz de datos como carpeta de trabajo):
  crea y edita archivos dentro de la carpeta de la empresa; lee y busca.
- **Solo analizar** (`dontAsk`): lee y propone; no toca ningún archivo.

En los dos, correr comandos, publicar, enviar o desplegar **queda bloqueado** y se
muestra como «pendiente de tu OK». Esas acciones se hacen en una sesión de Claude
Code, donde existe la aprobación paso a paso. Se permiten solas únicamente las
herramientas de solo lectura de los conectores instalados (búsqueda web, métricas,
estado de servidores).

## Programación

`services/scheduler.py` revisa cada 30 segundos. Una tarea programada es **«ejecutar
sola»** (entra en la fila a su hora; si es recurrente, se reprograma) o **«solo
recordarme»** (queda como recordatorio en Hoy). Solo corre con el panel abierto: el
arranque automático al iniciar sesión (`ideasbox panel autostart on`) lo resuelve en
macOS (LaunchAgent), Linux (autostart del escritorio) y Windows/WSL (carpeta Inicio).

## Dónde se guarda cada cosa

```text
$DATA_ROOT/05-OPERACIONES/panel/panel.db      tareas, ejecuciones, conversaciones, recordatorios
$DATA_ROOT/05-OPERACIONES/panel/runs/*.jsonl  salida de cada ejecución
~/.config/ideasbox/secrets/panel.env          credenciales opcionales (600)
~/.local/share/ideasbox/panel                 código instalado
~/.local/state/ideasbox/panel.{pid,log}       proceso y log
```

## Credenciales, todas opcionales

- `OPENROUTER_API_KEY` — si está, «crear tarea con palabras» usa OpenRouter en vez de
  Claude Code.
- `NOTIFY_CHANNEL` (`webhook` o `evolution`) — aviso de «tarea lista para revisar»
  (Slack, Discord, n8n o cualquier endpoint HTTP; o WhatsApp por Evolution API).

## Seguridad

Escucha en `127.0.0.1` y no tiene autenticación, porque es una herramienta de un
puesto de trabajo y no se expone a la red. No lo pongas detrás de un proxy público sin
ponerle autenticación primero. Las acciones de mantenimiento son una lista cerrada:
el panel no ejecuta comandos arbitrarios. Las claves de un conector van directo a su
archivo 600 y no quedan en el historial.

## Desarrollo

```bash
cd backend && ./venv/bin/uvicorn main:app --reload --port 8420
cd frontend && npm run dev -- --port 5173
```

Vite proxea `/api` al backend. Para el build de producción, `npm run build` deja
`frontend/dist` y el mismo FastAPI lo sirve (con las rutas de la SPA).
