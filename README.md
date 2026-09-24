# Ideas Box

> Tu empresa online híbrida, en una caja. Un proyecto de **IdeasDevOps & Disruptia AI**.

Convierte una máquina recién instalada —Ubuntu, Linux Mint, Debian o macOS— en un puesto de
trabajo completo para operar una empresa con agentes de IA: agentes por área, skills, memoria
canónica persistente y conectores MCP a las herramientas del negocio.

## Empezar

1. **Bajá Ideas Box.** Abrí la Terminal (en Mac: Aplicaciones → Utilidades → Terminal) y pegá:
   ```bash
   git clone https://github.com/ideasdevops/ideas-box.git ~/ideas-box
   ```
   Si avisa que falta git: en Linux, `sudo apt install -y git`; en Mac, aceptá la ventana que
   ofrece instalar las herramientas de Apple y volvé a pegar la línea.
2. **Abrí el menú.** En Mac, doble clic en **Ideas Box.command**, dentro de la carpeta
   `ideas-box` de tu usuario. En Linux, en la Terminal: `bash ~/ideas-box/bin/ideasbox`
3. Elegí **«Instalar mi Ideas Box»** y respondé las preguntas.

Al terminar queda el ícono **Ideas Box** en tu Escritorio (Mac) o en el menú de aplicaciones
(Linux). Desde ahí se hace todo lo demás, sin escribir comandos.

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
| **Conectores MCP** | Búsqueda web, grafo de código, bandeja de atención, panel de servidores, SSH, redes sociales, video |
| **Panel de control** | Tablero web local para programar tareas a los agentes (opcional) |
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

La frase también se puede escribir directo: `ideasbox conectar chatwoot`, `ideasbox crear una
habilidad`. Y dentro de Claude se pide como a una persona: *"conectá mi Instagram"*, *"creá una
habilidad para responder presupuestos"*.

### Para usuarios avanzados

Todo lo del menú tiene su comando:

```bash
bash install.sh          # instalar (= «Instalar mi Ideas Box»)
ideasbox doctor          # ¿está todo sano?
ideasbox status          # resumen corto
ideasbox mcp list        # conectores disponibles
ideasbox mcp add chatwoot
ideasbox mcp new         # conector propio a partir de su línea npx/uvx
ideasbox skills new      # habilidad propia
ideasbox skills update   # actualizar los packs de terceros
ideasbox sync            # regenerar agentes y symlinks
ideasbox backup          # respaldo del árbol canónico
ideasbox update          # actualizar todo
ideasbox panel install   # tablero web local de tareas
ideasbox panel start     # abrirlo en http://127.0.0.1:8420
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
| macOS 13 o posterior (Intel y Apple Silicon) | Herramientas de línea de comandos de Xcode. En Apple Silicon con macOS 15+ el script instala Homebrew si falta; en Intel o en macOS más viejo usa el Homebrew que ya tengas o, si no hay, baja jq, Python y Node sueltos a `~/.local/bin` |

macOS 12 (Monterey) y anteriores no sirven: Claude Code solo publica binarios para macOS 13 en
adelante, y el instalador corta ahí con las alternativas. En Macs que no pasan de Monterey, lo
recomendable es instalarles Linux Mint o Ubuntu.

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
