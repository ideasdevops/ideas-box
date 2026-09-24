# Primeros pasos con Ideas Box

Guía para la persona que acaba de instalar el stack y nunca trabajó con agentes.

Todo se hace desde el ícono **Ideas Box** (Escritorio en Mac, menú de aplicaciones en Linux). Si
preferís la terminal, escribí `ideasbox`: es el mismo menú.

## 1. Comprobar que quedó bien

En el menú: **«Revisar que todo esté bien»**.

Tiene que decir "Stack sano". Si dice que la raíz de datos no está disponible y la pusiste en un
disco aparte, montalo y repetí.

## 2. Hablar con tus agentes

En el menú: **«Hablar con mis agentes»**. La primera vez, Claude te pide iniciar sesión con tu
cuenta.

Probá con: **"mostrame qué agentes tengo y qué hace cada uno"**.

## 3. Cargar el contexto de tu empresa

Los agentes ya saben cómo trabajar, pero no saben nada de tu negocio todavía. Dedicale la primera
sesión a eso:

- **"Guardá en memoria que mi empresa hace X, vende Y y sus clientes son Z"** → lo escribe en
  `.claude/memory/shared/`.
- **"Creá la carpeta del cliente Fulano en 02-CLIENTES y anotá lo que sabemos de él"**.
- **"Anotá que los martes cierro pedidos a las 18"** → cualquier regla operativa que hoy solo está
  en tu cabeza.

Cuanto más contexto real cargues, menos vas a tener que repetir después.

## 4. Pedirle trabajo a un agente

Se invocan por nombre:

- *"Usá `sales-crm` para armar una propuesta para Fulano"*
- *"Que `ops-support` revise cómo está el servidor de producción"*
- *"`content-strategist`, armame el calendario de contenido de octubre"*

Si no sabés cuál, pedíselo a `agents-orchestrator`: reparte el trabajo entre las áreas.

## 5. Conectar tus herramientas

En el menú: **«Conectar una herramienta»**, y elegí de la lista (Chatwoot, Instagram, tu
servidor…). Si no está, **«Crear un conector nuevo»**: Claude te ayuda a encontrar uno confiable.

Cada conector pide sus credenciales y las guarda cifradas por permisos en
`~/.config/ideasbox/secrets/`, fuera de la configuración de Claude.

Después de agregar uno, los agentes que lo usan se actualizan solos.

## 6. Enseñarles tu forma de trabajo

Si hay algo que hacés siempre igual (responder presupuestos, publicar una promo, cerrar el mes),
convertilo en una habilidad: menú → **«Crear una habilidad nueva»**. Te pregunta el nombre y
para qué sirve, y Claude te ayuda a escribir los pasos. Desde ahí, los agentes la usan solos.

También podés pedírselo directo a Claude: *"creá una habilidad para responder presupuestos"*.

## 7. Reglas que conviene conocer

- **Nada irreversible pasa sin que lo apruebes**: mandar un mensaje a un cliente, publicar,
  gastar en pauta, reiniciar un servidor, borrar algo.
- **Los agentes son archivos de texto** en `<tu-raíz-de-datos>/.claude/agents/`. Si uno no trabaja
  como querés, editalo. Es la forma esperada de usar el stack, no un hack.
- **La memoria es tuya y es un archivo**: `.claude/memory/MEMORY.md` es el índice. Se puede leer,
  corregir y versionar.

## Problemas frecuentes

| Síntoma | Qué pasa |
|---|---|
| "No encuentra mis agentes" | La raíz de datos no está montada. Menú → «Revisar que todo esté bien» |
| Un conector no responde | Credenciales vencidas o vacías: revisá `~/.config/ideasbox/secrets/<servidor>.env` |
| Editaste un agente y volvió atrás | No volvió: mirá si quedó un archivo `.nuevo` al lado con la versión del stack |
| Tras actualizar falta una skill | Menú → «Actualizar todo» |
| La instalación se cortó (error, Ctrl+C, se cerró la terminal) | Abrí de nuevo el menú, elegí «Terminar de instalar mi Ideas Box» y respondé que sí a retomar: sigue desde el paso que quedó, con las respuestas que ya diste |
| En Mac: "command not found: brew" | Abrí una terminal nueva después de instalar Homebrew y repetí |
| En Mac: "Homebrew on macOS is only supported on Apple Silicon processors" | Es el instalador oficial de Homebrew, que ya no soporta Intel. Actualizá Ideas Box (en la Terminal: `cd ~/ideas-box && git pull`) y volvé a instalar: en esos Mac sigue sin Homebrew |
| En Mac: corta diciendo que macOS es anterior a 13 | Claude Code no corre en Monterey o anteriores. Ver alternativas en el README (Linux en ese equipo, o subir de versión de macOS) |
| En Mac: no aparece el disco externo | Tiene que estar montado en `/Volumes` y con permiso de escritura |
