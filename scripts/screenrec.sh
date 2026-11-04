#!/data/data/com.termux/files/usr/bin/bash
# screenrec.sh - grabacion de pantalla con scrcpy desde el propio dispositivo
# uso: screenrec.sh start|stop|toggle|status
set -u

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib"

STATE="$HOME/.screenrec"
OUT="/sdcard/DCIM/ScreenRecorder"
PIDFILE="$STATE/pid"
LOGFILE="$STATE/log"
SERIAL="${SERIAL:-}"
if [ -z "$SERIAL" ]; then
    _P=$(/system/bin/getprop service.adb.tcp.port 2>/dev/null)
    [ -z "$_P" ] || [ "$_P" = "0" ] && _P=5555
    SERIAL="127.0.0.1:$_P"
fi
APP="dev.local.screentile"
MEDIA_STREAM=3

# Intentar prioridad alta para la grabacion. En Termux esto suele funcionar
# aunque no se sea root, porque el limite RLIMIT_NICE lo permite.
renice -n -10 $$ >/dev/null 2>&1 || true

# ajustes opcionales pasados por el tile (max-size, fps, codec)
ARG_SIZE="${2:-}"
ARG_FPS="${3:-}"
ARG_CODEC="${4:-}"
ARG_BITRATE="${5:-}"
ARG_ABITRATE="${6:-}"
ARG_ASOURCE="${7:-}"

# parametros (se pueden sobreescribir por entorno)
MAX_SIZE="${MAX_SIZE:-2400}"     # 2400 -> 1078x2400 (punto dulce del encoder a 120fps)
MAX_FPS="${MAX_FPS:-120}"
BITRATE="${BITRATE:-}"
VCODEC="${VCODEC:-h265}"
ASOURCE="${ASOURCE:-playback}"   # playback = audio interno de las apps
ABITRATE="${ABITRATE:-128K}"

mkdir -p "$STATE" "$OUT" 2>/dev/null
echo "$(date '+%F %T') uid=$(id -u) args=$*" >>"$STATE/debug.log"

notify() {
    "${PREFIX}/bin/am" broadcast -a "$APP.STATE" --es state "$1" \
        -n "$APP/.StateReceiver" >/dev/null 2>&1
}

is_recording() {
    [ -f "$PIDFILE" ] || return 1
    local p
    p=$(cat "$PIDFILE" 2>/dev/null) || return 1
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

ensure_adb() {
    if [ "$(/system/bin/getprop service.adb.tcp.port 2>/dev/null)" != "5555" ]; then
        # solo si corremos como root podemos reiniciar adbd
        if [ "$(id -u)" = "0" ]; then
            /system/bin/setprop service.adb.tcp.port 5555 2>/dev/null
            stop adbd 2>/dev/null
            start adbd 2>/dev/null
            sleep 1.5
        fi
    fi
    adb start-server >/dev/null 2>&1
    adb connect "$SERIAL" >/dev/null 2>&1
    local i
    for i in $(seq 1 25); do
        [ "$(adb -s "$SERIAL" get-state 2>/dev/null)" = "device" ] && return 0
        adb connect "$SERIAL" >/dev/null 2>&1
        sleep 0.3
    done
    return 1
}

start_rec() {
    if is_recording; then
        notify recording
        return 0
    fi
    if ! ensure_adb; then
        echo "adb no disponible" >>"$LOGFILE"
        notify idle
        return 1
    fi

    # sobrescribe parametros si se pasaron (desde el tile)
    [ -n "${ARG_SIZE:-}" ] && MAX_SIZE="$ARG_SIZE"
    [ -n "${ARG_FPS:-}" ] && MAX_FPS="$ARG_FPS"
    [ -n "${ARG_CODEC:-}" ] && VCODEC="$ARG_CODEC"
    [ -n "${ARG_BITRATE:-}" ] && BITRATE="$ARG_BITRATE"
    if [ -n "${ARG_ABITRATE:-}" ]; then
        case "$ARG_ABITRATE" in
            *K|*k) ABITRATE="$ARG_ABITRATE" ;;
            *) ABITRATE="${ARG_ABITRATE}K" ;;
        esac
    fi
    if [ -n "${ARG_ASOURCE:-}" ]; then
        ASOURCE="$ARG_ASOURCE"
    fi
    case "$ASOURCE" in
        playback|mic|both|none) ;;
        *) ASOURCE=playback ;;
    esac

    # scrcpy solo admite una fuente de audio por sesion.
    # "both" usa voice-performance (microfono + reproduccion del dispositivo).
    local -a AUDIO_ARGS=()
    case "$ASOURCE" in
        none)
            AUDIO_ARGS+=(--no-audio)
            ;;
        both)
            AUDIO_ARGS+=(--audio-source=voice-performance --audio-bit-rate="$ABITRATE")
            ;;
        mic)
            AUDIO_ARGS+=(--audio-source=mic --audio-bit-rate="$ABITRATE")
            ;;
        *)
            ASOURCE=playback
            AUDIO_ARGS+=(--audio-source=playback --audio-dup --audio-bit-rate="$ABITRATE")
            ;;
    esac

    # resolver bitrate: 0 o vacio = automatico por scrcpy (se omite el flag)
    if [ "${BITRATE:-}" = "0" ]; then
        BITRATE=""
    elif [ -n "${BITRATE:-}" ]; then
        b=$(printf '%s' "$BITRATE" | tr -cd '0-9')
        [ -n "$b" ] && BITRATE="${b}M"
    else
        case "${MAX_SIZE}:${MAX_FPS}" in
            2400:60)  BITRATE=25M ;;
            2400:*)   BITRATE=50M ;;
            1600:60)  BITRATE=12M ;;
            1600:*)   BITRATE=20M ;;
            2560:60)  BITRATE=30M ;;
            2560:*)   BITRATE=40M ;;
            3840:60)  BITRATE=50M ;;
            3840:*)   BITRATE=80M ;;
            *)        BITRATE=25M ;;
        esac
    fi

    local file
    file="$OUT/scrcpy-$(date +%Y%m%d-%H%M%S).mkv"

    : >"$LOGFILE"
    echo "$file" >"$STATE/file"
    echo "$VCODEC" >"$STATE/vcodec"
    echo "$ASOURCE" >"$STATE/asource"
    echo "$ABITRATE" >"$STATE/abitrate"
    export SDL_VIDEODRIVER=dummy
    export PIDFILE
    # setsid: desacopla scrcpy de la sesion de Termux para que no lo maten
    # cuando el comando lanzado por el tile termina
    setsid "${PREFIX}/bin/bash" -c 'echo $$ >"$PIDFILE"; exec scrcpy "$@"' _ \
        -s "$SERIAL" -N \
        --record="$file" \
        --max-size="$MAX_SIZE" \
        --min-size-alignment=8 \
        --max-fps="$MAX_FPS" \
        --video-codec="$VCODEC" \
        ${BITRATE:+--video-bit-rate=$BITRATE} \
        "${AUDIO_ARGS[@]}" \
        --no-control \
        >>"$LOGFILE" 2>&1 </dev/null &

    sleep 1.5
    if is_recording; then
        notify recording
        return 0
    else
        rm -f "$PIDFILE"
        notify idle
        return 1
    fi
}

stop_rec() {
    if is_recording; then
        local p i
        p=$(cat "$PIDFILE")
        notify idle
        kill -INT "$p" 2>/dev/null
        for i in $(seq 1 20); do
            kill -0 "$p" 2>/dev/null || break
            sleep 0.2
        done
        kill -TERM "$p" 2>/dev/null
        sleep 0.3
    fi
    rm -f "$PIDFILE"
    notify idle

    # convertir el mkv a mp4 y borrar el mkv original
    local src codec tmp dir base dst asource abitrate
    local -a tag_args=() audio_args=()
    if [ -f "$STATE/file" ]; then
        src=$(cat "$STATE/file" 2>/dev/null)
        if [ -n "$src" ] && [ -f "$src" ]; then
            dir=$(dirname "$src")
            base=$(basename "$src" .mkv)
            dst="$dir/$base.mp4"
            tmp="$dir/$base.tmp.mp4"
            codec=$(cat "$STATE/vcodec" 2>/dev/null || echo h265)
            asource=$(cat "$STATE/asource" 2>/dev/null || echo playback)
            abitrate=$(cat "$STATE/abitrate" 2>/dev/null || echo 128K)
            case "$codec" in
                h265|hevc) tag_args=(-tag:v hvc1) ;;
            esac
            [ "$asource" != "none" ] && audio_args=(-c:a aac -b:a "$abitrate")
            if ffmpeg -y -hide_banner -loglevel error -i "$src" \
                    -c:v copy "${audio_args[@]}" \
                    "${tag_args[@]}" -movflags +faststart "$tmp" \
                    >>"$LOGFILE" 2>&1; then
                mv -f "$tmp" "$dst"
                rm -f "$src"
                # avisar al MediaStore del nuevo .mp4
                "${PREFIX}/bin/am" broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
                    -d "file://$dst" >/dev/null 2>&1
                echo "$(date '+%F %T') convertido $src -> $dst" >>"$LOGFILE"
            else
                rm -f "$tmp"
                "${PREFIX}/bin/am" broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
                    -d "file://$src" >/dev/null 2>&1
                echo "$(date '+%F %T') conversion fallo, se conserva $src" >>"$LOGFILE"
            fi
        fi
    fi
    return 0
}

case "${1:-toggle}" in
    start)  start_rec ;;
    stop)   stop_rec ;;
    toggle) if is_recording; then stop_rec; else start_rec; fi ;;
    status) if is_recording; then echo recording; else echo idle; fi ;;
    *) echo "uso: $0 start|stop|toggle|status" >&2; exit 2 ;;
esac
