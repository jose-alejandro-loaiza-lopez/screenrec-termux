#!/data/data/com.termux/files/usr/bin/bash
# screenrec-cleanup - elimina herramientas de compilacion que ya no hacen falta
# para usar la app. No toca scrcpy, ffmpeg ni adb.
set -u

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PATH"

BUILD_PKGS=(git openjdk-17 openjdk-21 openjdk-17-x openjdk-21-x d8 aapt2 apksigner)
ASSUME_YES=0
DRY_RUN=0

usage() {
    echo "uso: $0 [--yes|-y] [--dry-run|-n]"
    echo
    echo "Elimina git, JDK, d8, aapt2 y apksigner (solo necesarios para compilar),"
    echo "y limpia la cache de paquetes de Termux."
    echo "Conserva scrcpy, ffmpeg, android-tools y x11-repo."
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes)     ASSUME_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "opcion desconocida: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

TO_REMOVE=()
for p in "${BUILD_PKGS[@]}"; do
    if dpkg -s "$p" >/dev/null 2>&1; then
        TO_REMOVE+=("$p")
    fi
done

if [ "${#TO_REMOVE[@]}" -eq 0 ]; then
    echo "No hay paquetes de compilacion instalados."
else
    echo "Paquetes de compilacion instalados (no necesarios para grabar):"
    printf '  - %s\n' "${TO_REMOVE[@]}"
    echo
    echo "Se conservan: scrcpy, ffmpeg, android-tools y x11-repo."
fi

if [ "$DRY_RUN" = "1" ]; then
    echo "Modo simulacion: no se elimino nada."
    exit 0
fi

if [ "${#TO_REMOVE[@]}" -gt 0 ] && [ "$ASSUME_YES" = "0" ]; then
    printf '¿Eliminar estos paquetes? [s/N] '
    read -r answer
    case "$answer" in
        s|S|y|Y) ;;
        *) echo "Cancelado."; exit 0 ;;
    esac
fi

if [ "${#TO_REMOVE[@]}" -gt 0 ]; then
    pkg uninstall -y "${TO_REMOVE[@]}" || {
        echo "No se pudieron eliminar todos los paquetes." >&2
        exit 1
    }
fi

# Limpia dependencias huerfanas y .deb descargados.
pkg autoremove -y || true
pkg clean || true

echo
echo "Espacio disponible en Termux:"
df -h "$PREFIX" | tail -1
