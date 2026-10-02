# IdeasPackage — la empresa en un pendrive

`lib/paquete.sh` · comandos `ideasbox paquete {crear|buscar|abrir|guardar|cerrar|estado}` ·
en el menú: «Llevar mi empresa en un pendrive», y en una sesión abierta «Guardar ahora en el
pendrive» / «Cerrar mi empresa en este equipo».

## Qué hay en el pendrive

```
IdeasPackage/
  ideaspackage.json   manifiesto: propietario, empresa (nombre, slug, rubro), fechas, versión
  datos/              la raíz de datos completa (agentes, skills, memoria, trabajos, panel)
  enlaces.tsv         symlinks de la raíz de datos («@/…» = relativo a ella)
  perfil.conf         empresa.conf sin rutas del equipo (DATA_ROOT, STACK_SRC)
  conectores.tsv      mcp-installed.tsv
  secretos.gpg        credenciales de los conectores: tar cifrado con gpg (AES-256, S2K SHA-512)
  en-uso.json         solo mientras la empresa está abierta en algún equipo
```

Está pensado para pendrives **FAT32/exFAT** (los más comunes, que se leen en cualquier sistema):
no usa symlinks ni permisos dentro del pendrive. Los symlinks se anotan en `enlaces.tsv` y se
recrean al abrir; las credenciales, que necesitan permisos 600, viajan cifradas.

## Cómo se aísla del anfitrión

Al abrir, todo lo de la empresa invitada corre con un `HOME` propio:

```
~/.cache/ideaspackage/<slug>/
  home/        HOME invitado: ~/.claude, ~/CLAUDE.md, ~/.claude.json, ~/.config/ideasbox (nuevos)
  datos/       copia de trabajo de la raíz de datos (se sincroniza con el pendrive)
  cache/       lo reconstruible: mcp-servers (venvs, builds), bin, panel, claude — persiste
  entorno.sh   variables de la sesión (HOME, XDG_*, PATH, PANEL_PORT, IDEASPACKAGE_*)
$XDG_RUNTIME_DIR/ideaspackage-<slug>/   (tmpfs, en memoria)
  secretos/    credenciales descifradas (600) — el secrets/ del HOME invitado apunta acá
  clave        contraseña, para volver a cifrar al guardar
```

- `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME` y `XDG_STATE_HOME` también apuntan al HOME
  invitado (MX/JFlowOS definen `XDG_CONFIG_HOME`: si no, se escribiría en el del anfitrión).
- Los **programas** del anfitrión (claude, node) se usan desde el PATH; su **configuración** no.
  Si el equipo no tiene Claude Code, se instala en la caché invitada.
- La cuenta de Claude se inicia en cada sesión (queda en el HOME invitado y se borra al cerrar).
- El panel invitado usa otro puerto (8421 en adelante): no choca con el del anfitrión.
- gpg corre con un `--homedir` descartable (si no, crearía `~/.gnupg` en el anfitrión).
- Lanzadores y entradas de `~/.claude.json` se **regeneran** al abrir (tienen rutas absolutas del
  equipo): `paquete _hidratar` vuelve a correr `mcp_install` de cada conector con las credenciales
  descifradas, relinkea los packs y regenera agentes y settings.

## Guardar y cerrar

- `guardar`: rsync de `datos/` al pendrive (`--delete --delay-updates`, sin symlinks, margen de 2 s
  para FAT), `enlaces.tsv`, `perfil.conf`, `conectores.tsv`; las credenciales se vuelven a cifrar
  solo si cambiaron. Antes consolida el WAL de SQLite del panel.
- Guardado automático cada 10 min (`PKG_AUTOSAVE_MIN`), en un proceso propio (`setsid`).
- `cerrar`: guarda, apaga el autoguardado, el panel y todo proceso con
  `IDEASPACKAGE_SESION=<slug>` (menos el que cierra y sus padres), borra `en-uso.json` y borra
  `home/`, `datos/`, `entorno.sh` y las credenciales en memoria. Queda solo `cache/`.
- Si al abrir hay un `en-uso.json` de otro equipo (se cerró mal), avisa y pide confirmación.

## Probado (2026-10-01)

Sandbox con un dueño (empresa con agentes, memoria, pack humanizer y conector brave-search), un
pendrive **FAT32 real** montado con `udisksctl` y un anfitrión con su propio Ideas Box: saludo
«Hola Joaquín» desde el menú, contraseña incorrecta rechazada, apertura en ~10 s (7 s con caché),
conector reconstruido, trabajo + nota de memoria + archivo borrado + credencial renovada
sincronizados, autoguardado al minuto, cierre desde el menú invitado, y **huella sha256 del HOME
del anfitrión idéntica antes y después**. El dueño, en su equipo, no recibe el saludo por su
propio pendrive.

## Pendiente

- macOS y Windows/WSL.
- JFlowOS: aviso del sistema al conectar un pendrive con IdeasPackage.
- Panel invitado: se instala la primera vez si se elige «Abrir el panel» (usa `cache/panel`).
