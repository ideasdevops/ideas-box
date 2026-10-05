# Ideas Box

> Tu empresa online híbrida, en una caja. Un proyecto de **IdeasDevOps & Disruptia AI**.

Convierte una máquina recién instalada —Ubuntu, Linux Mint, Debian o macOS— en un puesto de
trabajo completo para operar una empresa con agentes de IA: agentes por área, skills, memoria
canónica persistente y conectores MCP a las herramientas del negocio.

## Empezar

1. **Abrí la Terminal** (en Mac: Aplicaciones → Utilidades → Terminal; en Windows 11: Ubuntu, ver
   abajo) y pegá esta línea:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/ideasdevops/ideas-box/main/instalar.sh | bash
   ```
2. **Seguí el asistente en el navegador.** Se abre solo: te pregunta el nombre y el rubro de tu
   empresa, dónde guardar los datos, qué habilidades y qué herramientas conectar, y muestra el
   avance de la instalación. No hace falta volver a la Terminal (dejala abierta hasta el final).
   Si se necesita la contraseña de tu equipo, la pide una ventana del sistema.

En Mac, la primera vez aparece la ventana de Apple para instalar sus herramientas de desarrollo:
aceptala y el asistente sigue solo. En **Windows 11**, primero instalá Ubuntu (en una terminal de
administrador: `wsl --install -d Ubuntu`), abrilo, y pegá la línea de arriba ahí; la contraseña de
Ubuntu se pide una vez en esa ventana.

Al terminar quedan en el Escritorio **Ideas Box** (el menú), **Archivos Ideas Box** y, si lo
instalaste, **Panel Ideas Box**. Desde ahí se hace todo lo demás, sin escribir comandos.

¿Preferís la terminal? `bash ~/ideas-box/install.sh` hace la misma instalación con preguntas
en la terminal (útil por SSH o en servidores).

📄 **Manual de usuario completo, en PDF:** [`docs/manual/Manual-Ideas-Box.pdf`](docs/manual/Manual-Ideas-Box.pdf)
— instalación en Linux y macOS, el asistente paso por paso, los agentes, los conectores y
resolución de problemas. Se regenera con `bash docs/manual/build.sh`.

Una sola pasada guiada. Al terminar, «Hablar con mis agentes» abre una sesión que ya conoce tu empresa.

## Qué instala

| Capa | Qué es |
|---|---|
| **Base** | Node, Python, ffmpeg, git, Claude Code |
| **Raíz de datos** | Un disco, una partición o una carpeta del home, con la estructura de la empresa |
| **16 agentes** | core, dev, ops, qa, ventas, marketing, contenido, clientes — con el nombre de *tu* empresa |
| **~20 skills propios** | Procedimientos de trabajo: bugfix, release, propuestas, campañas, bitácoras, memoria |
| **Packs de skills** | Marketing, diseño y disciplina de código, clonados de sus repos originales |
| **Conectores MCP** | Búsqueda web, grafo de código, bandeja de atención, panel de servidores, SSH, redes sociales, video, y generación con IA recomendada (ElevenLabs, Kling, Renoise) |
| **Panel de control** | Tablero web local para programar tareas a los agentes (opcional), con su propio ícono «Panel Ideas Box» en el Escritorio |
| **Reglas** | Autonomía, zonas protegidas y qué requiere aprobación explícita |

## Lo que NO hace

- **No toca la tabla de particiones.** Si querés un disco dedicado, el instalador te dice cómo
  crearlo y después lo adopta.
- **No guarda credenciales en `~/.claude.json`.** Cada conector arranca por un lanzador que carga
  su `.env` con permisos 600.
- **No trae datos de nadie.** Los agentes son plantillas: se completan con los datos de tu empresa
  durante la instalación.
- **No despliega ni publica por su cuenta.** Toda acción irreversible hacia afuera pide aprobación.

## Usarlo día a día

Abrí el ícono **Ideas Box** (o escribí `ideasbox` en una terminal) y elegí una opción, o escribí
con tus palabras lo que querés hacer:

| Querés… | En el menú |
|---|---|
| Trabajar con tus agentes | «Hablar con mis agentes» |
| Saber si todo anda bien | «Revisar que todo esté bien» |
| Sumar conocimientos (marketing, diseño, código…) | «Sumar habilidades» |
| Conectar Chatwoot, Instagram, tu servidor… | «Conectar una herramienta» |
| Enseñarles una forma de trabajo tuya | «Crear una habilidad nueva» |
| Conectar algo que no está en la lista | «Crear un conector nuevo» |
| Tener la última versión | «Actualizar todo» |
| Guardar una copia de todo | «Hacer un respaldo» |
| Llevar tu empresa en un pendrive | «Llevar mi empresa en un pendrive» |

La frase también se puede escribir directo: `ideasbox conectar chatwoot`, `ideasbox crear una
habilidad`. Y dentro de Claude se pide como a una persona: *"conectá mi Instagram"*, *"creá una
habilidad para responder presupuestos"*.

### Tu empresa en un pendrive (IdeasPackage)

Con «Llevar mi empresa en un pendrive» se guarda **toda la empresa** —agentes, habilidades,
conectores, memoria y lo que generaron tus agentes— en un pendrive o disco externo, con las
credenciales de los conectores **cifradas con una contraseña**.

En cualquier otro equipo con Ideas Box (aunque sea de otra persona y tenga su propia empresa),
conectá el pendrive y abrí Ideas Box: te saluda por tu nombre y te pregunta si querés iniciar tu
empresa ahí. Trabajás en una sesión aparte —con tu cuenta de Claude— que **no toca nada** de la
configuración del dueño del equipo. Lo que hagas se guarda en el pendrive solo cada 10 minutos y
al cerrar; al cerrar, el equipo no conserva tus datos ni tus credenciales. Detalle técnico en
[docs/IDEASPACKAGE.md](docs/IDEASPACKAGE.md). Por ahora funciona en Linux (incluido JFlowOS).

### Para usuarios avanzados

Todo lo del menú tiene su comando:

```bash
bash install.sh --gui    # asistente gráfico en el navegador
bash install.sh          # la misma instalación, con preguntas en la terminal
ideasbox doctor          # ¿está todo sano?
ideasbox status          # resumen corto
ideasbox mcp list        # conectores disponibles
ideasbox mcp add chatwoot
ideasbox mcp new         # conector propio a partir de su línea npx/uvx
ideasbox skills new      # habilidad propia
ideasbox skills update   # actualizar los packs de terceros
ideasbox sync            # regenerar agentes y symlinks
ideasbox backup          # respaldo del árbol canónico
ideasbox icono           # volver a crear el ícono «Ideas Box» del Escritorio
ideasbox update          # actualizar todo
ideasbox panel install   # tablero web local de tareas
ideasbox panel open      # levantarlo y abrirlo en el navegador (http://127.0.0.1:8420)
ideasbox carpeta         # abrir la carpeta con lo que generan los agentes
ideasbox paquete crear   # IdeasPackage: empaquetar la empresa en un pendrive
ideasbox paquete abrir   # abrir la empresa de un pendrive conectado
ideasbox paquete guardar # guardar en el pendrive lo trabajado
ideasbox paquete cerrar  # guardar, cerrar y borrar todo rastro del equipo
```

## Cómo está organizado

```text
Ideas Box.command       ícono de doble clic (macOS): abre el menú
install.sh              instalador guiado, en 9 pasos
bin/ideasbox            CLI de mantenimiento
lib/                    un módulo por paso del instalador
catalog/mcp/*.mcp       un archivo declarativo por conector
catalog/skill-packs.tsv packs de terceros, con su repo de origen
catalog/tool-groups.tsv grupos de herramientas MCP que expanden los agentes
templates/claude/       agentes, skills, docs y memoria (con variables {{EMPRESA}}, {{DATA_ROOT}})
templates/home/         CLAUDE.md y hooks del home
docs/manual/            manual de usuario en PDF, con su fuente HTML regenerable
vendor/panel/           panel de control local (backend FastAPI + interfaz React)
tools/render.py         renderizador de plantillas
tools/check-leaks.sh    verifica que no se filtren datos ni credenciales
vendor/                 código propio que se distribuye con el stack
```

## Requisitos

| Sistema | Qué necesita |
|---|---|
| Ubuntu · Linux Mint · Debian | `apt`, usuario con sudo, `git` para clonar |
| Windows 11 (dentro de Ubuntu en WSL) | Ubuntu instalado con `wsl --install`; Ideas Box se instala en esa terminal de Ubuntu como en cualquier Linux. El ícono queda en el Escritorio y el menú Inicio de Windows. No hay versión nativa para Windows |
| macOS 14 (Sonoma) o posterior en Apple Silicon · macOS 15 (Sequoia) o posterior en Intel | Herramientas de línea de comandos de Xcode. En Apple Silicon con macOS 15+ el script instala Homebrew si falta; en Intel o en macOS más viejo usa el Homebrew que ya tengas o, si no hay, baja jq, Python y Node sueltos a `~/.local/bin` |

Por debajo de eso no sirve: el binario de codebase-memory (el conector de código del núcleo) pide
macOS 14 en Apple Silicon y macOS 15 en Intel, y Claude Code no arranca en macOS 12 o anterior.
En Macs que no llegan a esas versiones, lo recomendable es instalarles Linux Mint o Ubuntu.

También:

- Una cuenta de Claude con acceso a Claude Code.
- Las credenciales de los servicios que quieras conectar. Todo lo que no tengas a mano se puede
  agregar después con `ideasbox mcp add`.

**Estado de macOS: soportado pero todavía sin probar en hardware real.** El código está escrito
para el bash 3.2 y las utilidades BSD que trae el sistema, con Homebrew en lugar de apt y
`/Volumes` en lugar de particiones. Si algo falla ahí, abrí un issue con la salida del error.

Dos diferencias en Mac: Docker se instala aparte (Docker Desktop, no por script) y el "disco de
datos aparte" se resuelve con un volumen APFS o un disco externo montado en `/Volumes`.

## Autores

**IdeasDevOps & Disruptia AI.**

## Licencia

Copyright © 2026 IdeasDevOps & Disruptia AI.

Ideas Box es software libre, publicado bajo la **GNU Affero General Public License v3.0**
(AGPL-3.0) — ver [LICENSE](LICENSE). Podés usarlo, estudiarlo, modificarlo y vender servicios
sobre él, también comercialmente. Usarlo tal cual no te obliga a publicar nada.

La condición es una: si **distribuís una versión modificada**, o la **ofrecés a otros a través de
una red** (por ejemplo, como servicio en línea), tenés que entregar su código fuente completo bajo
esta misma licencia y conservar los avisos de copyright. Así Ideas Box sigue siendo abierto para
todos, incluso cuando alguien lo mejora.

Los packs de skills y los servidores MCP de terceros **no se redistribuyen**: se clonan de sus
repositorios originales durante la instalación, cada uno **bajo su propia licencia**, que puede
no ser AGPL. `catalog/` y `docs/TERCEROS.md` listan el origen de cada uno: revisalos antes de
usarlos comercialmente.
