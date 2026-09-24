# Panel de control

Tablero web local para programar tareas a los agentes del stack. Se instala con
`ideasbox panel install` y se levanta con `ideasbox panel start`.

No se distribuye compilado: el instalador copia esta carpeta a
`~/.local/share/ideasbox/panel`, crea el entorno Python y compila la interfaz ahí.

## Qué muestra

| Vista | De dónde salen los datos |
|---|---|
| **Chat** | Interpreta un pedido en lenguaje natural y crea la tarea ya ruteada al agente correcto |
| **Agentes** | Escanea `$DATA_ROOT/.claude/agents` en vivo |
| **Skills** | Escanea `$DATA_ROOT/.claude/skills` en vivo |
| **Tareas** | Único dato propio, en SQLite dentro de la raíz de datos |
| **Servidores** | Derivados de los conectores MCP instalados (`mcp-installed.tsv`) |

Agentes, skills y servidores son **solo lectura**: se agregan con `ideasbox sync`
y `ideasbox mcp add`, no desde el panel.

## Dónde se guarda cada cosa

```text
$DATA_ROOT/05-OPERACIONES/panel/panel.db   tareas e historial de chat
~/.config/ideasbox/secrets/panel.env       credenciales (opcionales, 600)
~/.local/share/ideasbox/panel              código instalado
~/.local/state/ideasbox/panel.{pid,log}    proceso y log
```

Las tareas viven en la raíz de datos a propósito: son datos de la empresa y
tienen que viajar con el backup, no quedarse en el home de una máquina.

## Credenciales, todas opcionales

Sin nada configurado el tablero funciona completo. `panel.env` habilita dos
funciones extra:

- `OPENROUTER_API_KEY` — el chat en lenguaje natural y la redacción de contenido.
- `NOTIFY_CHANNEL` (`webhook` o `evolution`) — el aviso de "tarea lista para
  revisar". El canal `webhook` sirve para Slack, Discord, n8n o cualquier
  endpoint HTTP; `evolution` manda un WhatsApp por Evolution API.

## La regla que no se negocia

**El panel nunca publica ni despliega solo.** Puede redactar contenido para las
tareas de `content-strategist` y `design-content`, y avisar que quedó listo. La
publicación real la hace una persona, o un agente en una sesión de Claude Code
con los conectores MCP instalados, que es donde existe el control de aprobación.

`auto_publicar` solo cambia el texto del aviso. Agregar acá una llamada real a
una API de publicación es una decisión de diseño, no un ajuste de configuración.

## Seguridad

Escucha en `127.0.0.1` y no tiene autenticación, porque es una herramienta de un
puesto de trabajo y no se expone a la red. No lo pongas detrás de un proxy
público sin ponerle autenticación primero.

## Desarrollo

```bash
cd backend && ./venv/bin/uvicorn main:app --reload --port 8420
cd frontend && npm run dev -- --port 5173
```

Vite proxea `/api` al backend. Para el build de producción, `npm run build` deja
`frontend/dist` y el mismo FastAPI lo sirve en `/`.
