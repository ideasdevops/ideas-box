# Ideas Box

> Tu empresa online híbrida, en una caja. Un proyecto de **IdeasDevOps & Disruptia AI**.

Convierte una máquina recién instalada —Ubuntu, Linux Mint, Debian o macOS— en un puesto de
trabajo completo para operar una empresa con agentes de IA: agentes por área, skills, memoria
canónica persistente y conectores MCP a las herramientas del negocio.

```bash
# Linux: una máquina limpia no trae git
sudo apt update && sudo apt install -y git

# macOS (13 o posterior): git viene con Xcode CLT; del resto se encarga el instalador
xcode-select --install     # si nunca lo instalaste

git clone https://github.com/ideasdevops/ideas-box.git
cd ideas-box
bash install.sh
```

Después de instalar, autenticá Claude Code una vez con `claude`.

📄 **Manual de usuario completo, en PDF:** [`docs/manual/Manual-Ideas-Box.pdf`](docs/manual/Manual-Ideas-Box.pdf)
— instalación en Linux y macOS, el asistente paso por paso, los agentes, los conectores y
resolución de problemas. Se regenera con `bash docs/manual/build.sh`.

Una sola pasada guiada. Al terminar, `claude` abre una sesión que ya conoce tu empresa.

## Qué instala

| Capa | Qué es |
|---|---|
| **Base** | Node, Python, ffmpeg, git, Claude Code |
| **Raíz de datos** | Un disco, una partición o una carpeta del home, con la estructura de la empresa |
| **16 agentes** | core, dev, ops, qa, ventas, marketing, contenido, clientes — con el nombre de *tu* empresa |
| **~20 skills propios** | Procedimientos de trabajo: bugfix, release, propuestas, campañas, bitácoras, memoria |
| **Packs de skills** | Marketing, diseño y disciplina de código, clonados de sus repos originales |
| **Conectores MCP** | Búsqueda web, grafo de código, bandeja de atención, panel de servidores, SSH, redes sociales, video |
| **Reglas** | Autonomía, zonas protegidas y qué requiere aprobación explícita |

## Lo que NO hace

- **No toca la tabla de particiones.** Si querés un disco dedicado, el instalador te dice cómo
  crearlo y después lo adopta.
- **No guarda credenciales en `~/.claude.json`.** Cada conector arranca por un lanzador que carga
  su `.env` con permisos 600.
- **No trae datos de nadie.** Los agentes son plantillas: se completan con los datos de tu empresa
  durante la instalación.
- **No despliega ni publica por su cuenta.** Toda acción irreversible hacia afuera pide aprobación.

## Después de instalar

```bash
ideasbox doctor          # ¿está todo sano?
ideasbox status          # resumen corto
ideasbox mcp list        # conectores disponibles
ideasbox mcp add chatwoot
ideasbox skills update   # actualizar los packs de terceros
ideasbox sync            # regenerar agentes y symlinks
ideasbox backup          # respaldo del árbol canónico
ideasbox update          # actualizar todo
```

## Cómo está organizado

```text
install.sh              instalador guiado, en 8 pasos
bin/ideasbox            CLI de mantenimiento
lib/                    un módulo por paso del instalador
catalog/mcp/*.mcp       un archivo declarativo por conector
catalog/skill-packs.tsv packs de terceros, con su repo de origen
catalog/tool-groups.tsv grupos de herramientas MCP que expanden los agentes
templates/claude/       agentes, skills, docs y memoria (con variables {{EMPRESA}}, {{DATA_ROOT}})
templates/home/         CLAUDE.md y hooks del home
docs/manual/            manual de usuario en PDF, con su fuente HTML regenerable
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

Ideas Box se publica bajo licencia **MIT** — ver [LICENSE](LICENSE). Usalo, modificalo y
vendé servicios sobre él; lo único que pedimos es que se mantenga el aviso de copyright.

Los packs de skills y los servidores MCP de terceros **no se redistribuyen**: se clonan de sus
repositorios originales durante la instalación, cada uno **bajo su propia licencia**, que puede
no ser MIT. `catalog/` y `docs/TERCEROS.md` listan el origen de cada uno: revisalos antes de
usarlos comercialmente.
