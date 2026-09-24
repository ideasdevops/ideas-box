#!/bin/bash
# Doble clic en macOS: abre el menú de Ideas Box en una Terminal, sin escribir comandos.
# Antes de instalar solo ofrece «Instalar mi Ideas Box».
cd "$(dirname "$0")" && exec bash bin/ideasbox menu
