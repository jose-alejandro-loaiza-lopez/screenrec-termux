#!/data/data/com.termux/files/usr/bin/bash
# install.sh - instala el tile y concede el permiso de Termux
set -euo pipefail

cd "$(dirname "$0")"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PATH"

# aviso si falta acceso a almacenamiento externo
if [ ! -d "$HOME/storage/shared" ]; then
    echo "AVISO: falta el permiso de almacenamiento."
    echo "Ejecutá 'termux-setup-storage' y aceptá el diálogo de Android."
fi

# instalar scripts de Termux si el repo los trae
if [ -d scripts ] && [ -f scripts/screenrec.sh ]; then
    mkdir -p "$HOME/bin"
    install -m 0755 scripts/screenrec.sh "$HOME/bin/screenrec.sh"
    if [ -f scripts/screenrec-cleanup.sh ]; then
        install -m 0755 scripts/screenrec-cleanup.sh "$HOME/bin/screenrec-cleanup"
    fi
fi

# asegurar que ~/bin este en PATH (idempotente)
if [ -f "$HOME/.bashrc" ]; then
    grep -q 'export PATH="\$HOME/bin:\$PATH"' "$HOME/.bashrc" || \
        echo 'export PATH="$HOME/bin:$PATH"' >>"$HOME/.bashrc"
else
    echo 'export PATH="$HOME/bin:$PATH"' >"$HOME/.bashrc"
fi

SERIAL="${SERIAL:-127.0.0.1:5555}"
APK="screenrec-tile.apk"
APP="dev.local.screentile"

adb connect "$SERIAL" >/dev/null 2>&1 || true
if [ "$(adb -s "$SERIAL" get-state 2>/dev/null)" != "device" ]; then
    echo "adb no conecta a $SERIAL (probá: adb connect $SERIAL)"
    exit 1
fi

adb -s "$SERIAL" install -r "$APK"
adb -s "$SERIAL" shell pm grant "$APP" com.termux.permission.RUN_COMMAND
echo "==> instalado $APP; volvé a tocar el tile en el Centro de control"
