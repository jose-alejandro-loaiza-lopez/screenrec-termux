# Grabar pantalla con scrcpy desde el propio teléfono

App/tile de Quick Settings (Centro de control) llamada **Grabar pantalla**. No usa root ni modifica el sistema: vive en `/data` (Termux) y `/sdcard`. El tile es solo un control remoto para `~/bin/screenrec.sh`, que lanza `scrcpy` conectado por TCP a `127.0.0.1:5555`.

## Qué quedó instalado

- `~/bin/screenrec.sh` — script de grabación (scrcpy + conversión + aviso al MediaStore).
- `~/bin/qs-tap.sh` — helper de prueba para tocar un tile por nombre (usa `uiautomator`).
- App `dev.local.screentile` (`screenrec-tile.apk`) — tile **Grabar pantalla** en el Centro de control + app de configuración.
- Fuentes: `~/projects/screenrec/src/...`
- `tiles`: agregado a `sysui_qs_tiles`.
- AVB y particiones del sistema intactas.

## Arquitectura

```
Tile del Centro de control
  ├─ toque: toggle grabar/detener
  └─ long-press: abre "Configurar grabación"
        │ Intent com.termux.RUN_COMMAND
        ▼
Termux RunCommandService  ->  ~/bin/screenrec.sh start|stop
        │
        │ ensure_adb() (adb connect 127.0.0.1:5555)
        ▼
scrcpy (setsid, audio-dup)  ->  /sdcard/DCIM/ScreenRecorder/scrcpy-FECHA.mkv
        │
        │ al detener: ffmpeg (.mkv -> .mp4, H.264/H.265 + AAC) y se borra el .mkv
        │ am broadcast MEDIA_SCANNER_SCAN_FILE
        │ am broadcast dev.local.screentile.STATE
        ▼
StateReceiver -> SharedPreferences -> tile se actualiza
```

## Uso

1. Abrir el Centro de control y tocar **Grabar pantalla** (el panel se cierra).
2. Tocar de nuevo para **detener**: el `.mkv` se convierte automáticamente a `.mp4` (H.264/H.265 + AAC) y se borra el `.mkv`. Ese `.mp4` queda en `/sdcard/DCIM/ScreenRecorder/`.
3. Configuración: abrir la app **Configurar grabación** (icono en el cajón) **o mantener presionado el tile** (en AOSP).

## Configuración disponible (app)

- **Resolución:** 720p / 1080p / 1440p / 4K
- **FPS:** 30 / 60 (por defecto) / 90 / 120
- **Codec de video:** H.264 (por defecto) / H.265 (HEVC)
- **Bitrate de video:** 0–100 Mbps (**0 = automático**, omite el flag y scrcpy usa su valor por defecto)
- **Audio:** 128 / 256 / 320 kbps

Los valores se guardan en `SharedPreferences` (`config`) y se usan al iniciar la siguiente grabación.

## Parámetros de `screenrec.sh` (CLI o entorno)

```bash
~/bin/screenrec.sh start [MAX_SIZE MAX_FPS VCODEC VBITRATE_Mbps ABITRATE_Kbps]
```

Variables de entorno disponibles:

```bash
MAX_SIZE=2400      # max-size que scrcpy usa (2400 => nativo 1080x2400)
MAX_FPS=60         # fps solicitados
BITRATE=           # vacío o 0 = automático por scrcpy; otherwise Mbps
VCODEC=h264        # h264 o h265
ASOURCE=playback   # playback (app audio, no silencia speaker con --audio-dup) | output | mic
ABITRATE=128K      # bitrate del audio (Opus/AAC)
SERIAL=...         # serial ADB; por defecto 127.0.0.1:5555
```

Ejemplos:

```bash
MAX_FPS=120 MAX_SIZE=1600 VCODEC=h265 ~/bin/screenrec.sh start
~/bin/screenrec.sh stop
~/bin/screenrec.sh status
~/bin/screenrec.sh toggle
```

## Cómo funciona (para no romper nada)

- La app **no usa root**: le manda un intent `com.termux.RUN_COMMAND` a Termux, que ejecuta el script como usuario normal de Termux.
- `scrcpy` se lanza con `setsid` y `--audio-dup` para que Termux no lo mate y el audio siga sonando en el teléfono.
- El estado se comparte por broadcast `dev.local.screentile.STATE` para que el tile refleje si está grabando o idle, también desde Termux.
- ADB local: `adb connect 127.0.0.1:5555` (adbd ya estaba en 5555). Si deja de estar, el script solo puede reiniciar adbd si corre como root, que es lo que intenta cuando corresponde.
- **MKV → MP4**: al detener, `ffmpeg` hace `-c:v copy` (H.264/H.265), re-encodea audio a AAC (bitrate seleccionado), `+faststart` y tag `hvc1` en H.265; si falla, se conserva el `.mkv`.
- **MediaStore**: se envía un broadcast para que Galería/Fotos/Telegram detecten el `.mp4`.
- El tile usa **actualización optimista**: cambia el estado al instante y se corrige después según el broadcast.

## Colapso del panel al tocar

El tile llama `TileService.startActivityAndCollapse(PendingIntent)` con una actividad `CollapseActivity` vacía (`Theme.NoDisplay`, sin historial ni task). En la práctica cierra el panel sin abrir la app.

## Audio en la grabación

- Fuente por defecto `playback`: captura el audio interno de las apps.
- Con **`--audio-dup`** el audio sigue saliendo por el altavoz del teléfono mientras se graba.
- El video puede tener audio capturado aunque el volumen del teléfono esté en 0 (la grabación usa el nivel que elige el usuario vía slider, y la conversión de audio **no** depende del nivel final del dispositivo).
- `ASOURCE=output` captura toda la salida, pero puede silenciar el dispositivo; `mic` graba el micrófono.

## Limitaciones / notas

- **Long-press para ajustes:** implementado con `android.service.quicksettings.action.QS_TILE_PREFERENCES` (igual que Caffeine). En ROMs AOSP abre Configurar grabación; en MIUI/HyperOS el OEM puede interceptar el long-press (editor de tiles).
- Sin root; todo es `/data` + Termux.
- No hay Gradle: el build es con `javac` + `d8` + `aapt2` + `apksigner`.
- Audio a 128/256/320 kbps (Opus → AAC).
- Contenedor `.mp4`: compatible con Galería; codec H.265 fue etiquetado como `hvc1` para mayor compatibilidad.

## Resolución y compatibilidad con otros dispositivos

- La app **no** asume una resolución fija: `Config.maxSize()` lee `DisplayMetrics` reales y calcula
  `--max-size = round(longSide * targetShort / shortSide)` (mínimo 320). Así funciona en pantallas
  de distinto aspecto (tall, wide, etc.).
- Etiquetas de UI y resultados esperados:
  - `720p`: target short = 720
  - `1080p`: target short = 1080
  - `1440p`: target short = 1440
  - `4K`: target short = 2160 (si el hardware no alcanza, scrcpy se limita al tamaño nativo)
- `--min-size-alignment=8` se fuerza en `screenrec.sh` para que las dimensiones sean múltiplos de 8;
  scrcpy aplica el máximo entre este y el requisito del codec.
- El serial ADB por defecto es `127.0.0.1:5555` (variable `SERIAL`). Si un dispositivo usa otro serial o
  adbd escucha en 0.0.0.0:5555, cámbialo por entorno o en la variable del script.

## Uso en otro dispositivo Android

Requisitos mínimos:

- Android 7+ con Quick Settings funcionando.
- Termux instalado (o una ruta equivalente de app-grabadora con permisos equivalentes).
- `scrcpy`, `ffmpeg`, `adb` disponibles en el PATH de Termux.
- `allow-external-apps = true` en `~/.termux/termux.properties`.
- Puerto ADB para loopback disponible (por defecto `5555`) o ajustar `SERIAL`.

Pasos:

1. Instalar dependencias en Termux:

   ```bash
   pkg install scrcpy ffmpeg android-tools
   ```

2. Verificar que `adbd` escuche en 5555. En algunos teléfonos hay que habilitarlo por única vez como root:

   ```bash
   setprop service.adb.tcp.port 5555
   stop adbd
   start adbd
   ```

   En otros (como el equipo original) ya estaba en 5555 y no hace falta.

3. Clonar/copiar `~/projects/screenrec/` al dispositivo y ajustar rutas si es necesario
   (el código asume `/data/data/com.termux/files/home` para Termux).

4. Compilar e instalar:

   ```bash
   cd ~/projects/screenrec
   ./build.sh
   ./install.sh
   ```

5. Agregar el tile **Grabar pantalla** al Centro de control (editor de tiles, si no aparece solo).

6. (Opcional) Probar desde Termux:

   ```bash
   ~/bin/screenrec.sh start
   ~/bin/screenrec.sh stop
   ~/bin/screenrec.sh status
   ```

Notas específicas por ROM:

- **MIUI/HyperOS:** el long-press del tile puede abrir el gestor de tiles en lugar de la app de
  configuración; se mantiene el icono de app como atajo confiable.
- **Pixel/Android puro:** long-press con `QS_TILE_PREFERENCES` abre Configurar grabación.
- **OEMs con control center:** pueden bloquear `startActivityAndCollapse`; si ocurre, el panel queda
  abierto y solo se actualiza el estado.

## Rebuild / reinstalación

```bash
cd ~/projects/screenrec
./build.sh                       # compila + firma -> screenrec-tile.apk
./install.sh                    # install + pm grant RUN_COMMAND
```

O manualmente:

```bash
adb -s 127.0.0.1:5555 install -r ~/projects/screenrec/screenrec-tile.apk
adb -s 127.0.0.1:5555 shell pm grant dev.local.screentile com.termux.permission.RUN_COMMAND
```

(el permiso `RUN_COMMAND` es peligroso y hay que volver a darlo tras reinstalar).

## Archivos fuente principales

| Archivo | Responsabilidad |
|---|---|
| `src/dev/local/screentile/ScreenTileService.java` | Tile, toggle, estado optimista, colapso del panel, envío a Termux |
| `src/dev/local/screentile/StateReceiver.java` | Recibe broadcasts de estado del script |
| `src/dev/local/screentile/Config.java` | SharedPreferences (`config`) |
| `src/dev/local/screentile/SettingsActivity.java` | UI de configuración (resolución, fps, codec, bitrate) |
| `src/dev/local/screentile/CollapseActivity.java` | Actividad vacía para colapsar el panel |
| `AndroidManifest.xml` | Servicio tile + receiver + activity |
| `~/bin/screenrec.sh` | ADB, scrcpy, conversión MKV→MP4, MediaStore |
| `~/bin/qs-tap.sh` | helper de prueba para tocar un tile |
| `build.sh` / `install.sh` | build + firma + instalación |
