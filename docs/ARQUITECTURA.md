# Arquitectura del stack

> IdeasDevOps & Disruptia

## La idea

El valor no está en Claude Code ni en los MCP: está en **la organización**. Un puesto de trabajo
con agentes sirve cuando hay una fuente de verdad, reglas de quién puede hacer qué, y memoria que
sobrevive a la sesión. Este repo empaqueta esas tres cosas.

## Decisiones de diseño

### 1. La fuente de verdad vive en la raíz de datos, no en el home

`~/.claude/{agents,skills}` contiene **solo symlinks** a `$DATA_ROOT/.claude/`. Consecuencias:

- reinstalar el sistema operativo no pierde nada;
- la raíz de datos se puede mover a otro disco o a otra máquina;
- un backup de una carpeta se lleva todo el conocimiento de la empresa.

El precio es que si la raíz no está montada, el stack queda a medias. Por eso hay un hook de
`SessionStart` que lo detecta y lo dice antes de que el agente empiece a trabajar a ciegas.

### 2. Los agentes declaran grupos de herramientas, no herramientas sueltas

Un agente con `mcp__easypanel-prod__restart_service` en su frontmatter, cuando ese servidor no
está instalado, **pierde la capacidad sin ningún error**: la herramienta simplemente no existe y
el agente nunca se entera. Es un modo de falla silencioso y caro.

Por eso las plantillas escriben `{{TOOLS easypanel:ops}}` y `tools/render.py` lo expande a una
línea por herramienta y por servidor realmente instalado, leyendo `mcp-installed.tsv`. Agregar un
servidor nuevo y correr `empresa sync` actualiza a todos los agentes que lo usan.

### 3. Los secretos no entran en la configuración de Claude

Cada conector se registra con `command` apuntando a `~/.config/empresa/launchers/<servidor>.sh`,
un script que carga `~/.config/empresa/secrets/<servidor>.env` (600) y hace `exec` del servidor
real. `~/.claude.json` queda sin un solo token, y `empresa doctor` avisa si alguno se filtró.

También resuelve el caso de los servidores que piden el token como argumento de línea de comandos
(visible en `ps`): el lanzador lo arma desde la variable de entorno.

### 4. Terceros se clonan, no se copian

Los packs de skills y los MCP de terceros se clonan de su upstream durante la instalación, con su
commit anotado en `locks.tsv`. El repo del stack no redistribuye código ajeno y los packs se
actualizan con `empresa skills update`.

### 5. El renderizador no pisa lo que editaste

`render.py` guarda el hash de lo último que generó. Si el archivo en destino cambió respecto de
eso, deja la versión nueva como `.nuevo` y avisa, en vez de sobrescribir. Los agentes están hechos
para ser editados por el dueño del stack.

### 6. Nada destructivo automático

El instalador no formatea, no reparticiona, no borra configuración previa: hace merge de
`settings.json`, respalda antes de sobrescribir y nunca reemplaza un archivo que no sea un symlink
que él mismo creó.

## Flujo de instalación

```text
1. deps        apt + Node ≥20 + Claude Code (+ Docker opcional)
2. profile     nombre, rubro, sitio, idioma, zona horaria  → ~/.config/empresa/empresa.conf
3. datastore   elección de disco/carpeta + estructura       → $DATA_ROOT
4. skill-packs clone de packs de terceros                   → $DATA_ROOT/01-RECURSOS-IA/20-VALIDADOS
5. mcp         clone/build + credenciales + lanzadores      → ~/.claude.json, secrets/
6. canonical   render de agentes, skills, docs, memoria     → $DATA_ROOT/.claude
7. link        symlinks de runtime                          → ~/.claude
8. settings    permisos, denegaciones y hook de arranque    → ~/.claude/settings.json
```

Cada paso es idempotente: volver a correr el instalador actualiza en vez de duplicar.

## Extender el stack

**Un conector nuevo**: agregá un `.mcp` en `catalog/mcp/` con su repo, cómo se compila, qué
credenciales pide y a qué grupo de herramientas pertenece. Si el grupo es nuevo, sumalo a
`catalog/tool-groups.tsv` y referencialo desde los agentes que lo usen.

**Un agente nuevo**: una plantilla en `templates/claude/agents/<dominio>/`, con `{{TOOLS grupo}}`
para lo que necesite. Aparece en el runtime con `empresa sync`.

**Otro idioma o rubro**: todo el texto visible sale de plantillas. Un fork con `templates/`
traducido es un stack en otro idioma sin tocar una línea de código.
