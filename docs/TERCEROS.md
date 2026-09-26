# Componentes de terceros

Ideas Box **no redistribuye** código ajeno: lo clona de su repositorio original durante la
instalación y anota el commit exacto en `~/.config/ideasbox/locks.tsv`. Cada componente queda bajo
su propia licencia; revisala antes de usarlo comercialmente.

## Packs de skills (`catalog/skill-packs.tsv`)

| Pack | Origen | Dominio |
|---|---|---|
| ponytail | github.com/DietrichGebert/ponytail | dev |
| humanizer | github.com/blader/humanizer | core |
| marketing | github.com/coreyhaines31/marketingskills | marketing |
| taste | github.com/Leonxlnx/taste-skill | dev |
| open-design | github.com/nexu-io/open-design | dev |
| strix | github.com/usestrix/strix | qa |
| kling | github.com/klingai-tech/skills (lo instala el conector `kling-cli`) | contenido |

## Servidores MCP (`catalog/mcp/*.mcp`)

| Conector | Origen |
|---|---|
| ponytail | github.com/DietrichGebert/ponytail |
| codebase-memory | github.com/DeusData/codebase-memory-mcp (binario de release, con checksum) |
| brave-search | github.com/brave/brave-search-mcp-server |
| chatwoot | github.com/hugoblanc/chatwoot-mcp |
| easypanel | github.com/dannymaaz/easypanel-mcp |
| instagram | github.com/jlbadano/ig-mcp |
| facebook | github.com/Livia-Zaharia/just_facebook_mcp |
| facebook-ads | github.com/gomarble-ai/facebook-ads-mcp-server |
| meta-ads | github.com/Mike25app/scaleforge-mcp-meta-ads |
| google-ads | github.com/Limetric/ads |
| youtube | github.com/ZubeidHendricks/youtube-mcp-server |
| video-audio | github.com/misbahsy/video-audio-mcp |
| inkscape | github.com/sandraschi/inkscape-mcp |
| gimp | github.com/maorcc/gimp-mcp |
| obs | github.com/royshil/obs-mcp |
| obsidian | github.com/cyanheads/obsidian-mcp-server |
| elevenlabs | github.com/elevenlabs/elevenlabs-mcp (oficial) |
| kling | https://kling.ai/mcp — servidor remoto oficial, no se descarga código (OAuth) |

## Herramientas CLI y plugins (`catalog/mcp/*.mcp` con `KIND="tool"`)

No son servidores MCP: los agentes las usan por Bash o como skills de Claude Code.

| Herramienta | Origen |
|---|---|
| renoise | plugin github.com/ArcoCodes/renoise-plugins-official + CLI que baja su propio instalador |
| kling-cli | paquete npm `@klingai/cli-global` (oficial) |

## Código propio distribuido con el stack

- `vendor/infra-ssh-mcp/` — servidor MCP de acceso SSH/Docker controlado, escrito para este stack.

## Antes de publicar el repo

Corré `bash tools/check-leaks.sh`. Verifica que no queden marcas de la empresa de origen,
credenciales con formato conocido ni rutas absolutas de un home concreto.
