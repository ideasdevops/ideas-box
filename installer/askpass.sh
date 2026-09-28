#!/bin/bash
# Ayudante SUDO_ASKPASS del asistente: sudo -A lo llama cuando necesita la contraseña
# de administrador y lee de su salida lo que la persona escribió en la ventana nativa.
# La contraseña va directo de la ventana a sudo: no pasa por el asistente ni se guarda.
# Si la persona cancela, sale con error y sudo falla (el asistente ofrece reintentar).
MSG="Ideas Box necesita tu contraseña de administrador para instalar programas del sistema. Es la misma con la que entrás a tu usuario."

if [ "$(uname -s)" = Darwin ]; then
  exec osascript \
    -e 'on run argv' \
    -e 'text returned of (display dialog (item 1 of argv) default answer "" with hidden answer buttons {"Cancelar", "Aceptar"} default button "Aceptar" cancel button "Cancelar" with title "Ideas Box" with icon caution)' \
    -e 'end run' "$MSG"
elif command -v zenity >/dev/null 2>&1; then
  exec zenity --password --title="Ideas Box — $MSG"
elif command -v kdialog >/dev/null 2>&1; then
  exec kdialog --title "Ideas Box" --password "$MSG"
fi
echo "No hay una ventana para pedir la contraseña (zenity o kdialog)." >&2
exit 1
