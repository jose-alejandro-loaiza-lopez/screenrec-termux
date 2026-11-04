# Grabar pantalla con scrcpy desde el propio teléfono

Aplicación Quick Settings (Centro de control) llamada **Grabar pantalla** que permite grabar la pantalla del mismo dispositivo sin root. El tile es un control remoto: dispara `~/bin/screenrec.sh`, que corre `scrcpy` conectado por TCP a `127.0.0.1:5555` (o al puerto detectado por el sistema).

## Qué incluye el repositorio

- `~/bin/screenrec.sh` — grabación con `scrcpy`, conversión MKV → MP4 y aviso al MediaStore.
- `~/bin/qs-tap.sh` — helper para abrir el panel y tocar un tile por `content-desc`.
- `dev.local.screentile` (`screenrec-tile.apk`) — tile en el Centro de control + app de configuración.
- Fuentes Java en `src/dev/local/screentile/`.
- `build.sh` / `install.sh` — compilación, firma e instalación automatizadas (install.sh también copia `scripts/` a `~/bin`).
- `scripts/screenrec.sh`, `scripts/qs-tap.sh` — scripts de Termux versionados en el repo.
- `AndroidManifest.xml` — servicio tile, receiver y activity.
- `README.md`.

## Características

- Tile **Grabar pantalla / Grabando pantalla** en el Centro de control.
- Al tocar: alterna grabar/detener, muestra el cambio al instante y cierra el panel automáticamente.
- Long-press del tile: abre **Configurar grabación** (vía `QS_TILE_PREFERENCES`).
- App de configuración para elegir:
  - Resolución: 720p / 1080p / 1440p / 4K
  - FPS: 30 / 60 (por defecto) / 90 / 120
  - Codec: H.264 (por defecto) / H.265 (HEVC)
  - Bitrate de video: 0–100 Mbps (0 = automático por scrcpy)
  - Audio: 128 / 256 / 320 kbps
- Grabación en `.mkv`, conversión automática a `.mp4` (H.264/H.265 + AAC) y borrado del `.mkv`.
- `--audio-dup` para que el audio siga sonando en el teléfono mientras se graba.
- Resolución calculada dinámicamente según las dimensiones reales del display.
- Aviso al MediaStore para que Galería/Fotos/Telegram detecten el `.mp4`.
- Sin root ni modificaciones del sistema (todo en `/data`).

## Cómo funciona

1. El tile envía `com.termux.RUN_COMMAND` a Termux.
2. `screenrec.sh` ejecuta `ensure_adb()` (connect a `127.0.0.1:$PORT` o al puerto detectado).
3. Lanza `scrcpy` con `setsid`, `--max-size`, `--min-size-alignment=8`, `--audio-source=playback`, `--audio-dup`, etc.
4. Al detener envía `SIGINT` a scrcpy (flush correcto del archivo).
5. Convierte el `.mkv` a `.mp4` con `ffmpeg` (`-c:v copy`, audio AAC, `+faststart`, tag `hvc1` en H.265).
6. Notifica al MediaStore y envía broadcast `dev.local.screentile.STATE` para actualizar el tile.

## Requisitos

- Android 7+
- Termux
- Dependencias en Termux: `scrcpy`, `ffmpeg`, `android-tools` (ADB)
- `allow-external-apps = true` en `~/.termux/termux.properties`

## Instalación

```bash
pkg install scrcpy ffmpeg android-tools
cd ~/projects/screenrec
./build.sh
./install.sh
```

`install.sh` instala el APK y concede el permiso `com.termux.permission.RUN_COMMAND`.

Rebuild manual:

```bash
cd ~/projects/screenrec
./build.sh
adb -s 127.0.0.1:5555 install -r screenrec-tile.apk
adb -s 127.0.0.1:5555 shell pm grant dev.local.screentile com.termux.permission.RUN_COMMAND
```

## Uso desde CLI

```bash
~/bin/screenrec.sh start
~/bin/screenrec.sh stop
~/bin/screenrec.sh status
~/bin/screenrec.sh toggle
```

Parámetros por entorno o argumentos:

```bash
MAX_SIZE=2400 MAX_FPS=60 VCODEC=h264 BITRATE= BITRATE_AUDIO= ABITRATE=128K \
  ~/bin/screenrec.sh start
```

También se pueden pasar posicionalmente:

```bash
~/bin/screenrec.sh start <max-size> <fps> <codec> <video-mbps> <audio-kbps>
```

## Detección de ADB

- `SERIAL` puede sobrescribirse por entorno (`SERIAL=127.0.0.1:PORT`).
- Si `SERIAL` no está definido, el script usa el sistema: `service.adb.tcp.port`.
- Si adbd no está en TCP y el usuario es root, intenta habilitar 5555 automáticamente.

## Compatibilidad y otros dispositivos

- La resolución de salida se calcula con las dimensiones reales del display, por lo que se adapta a pantallas anchas, estrechas o de distintas relaciones de aspecto.
- En MIUI/HyperOS el long-press del tile puede abrir el editor de tiles en lugar de Configurar grabación; el icono de app sigue funcionando.
- El build no depende de Android Studio ni Gradle; usa `javac`, `d8`, `aapt2` y `apksigner`. `build.sh` genera un `ks.jks` de desarrollo si no existe.

## Archivos fuente principales

| Archivo | Responsabilidad |
|---|---|
| `ScreenTileService.java` | tile, toggle, estado optimista, colapso del panel, envío a Termux |
| `StateReceiver.java` | recepción de broadcasts de estado |
| `Config.java` | SharedPreferences (`config`) |
| `SettingsActivity.java` | UI de configuración (resolución, fps, codec, bitrate) |
| `CollapseActivity.java` | actividad vacía para colapsar el panel |
| `AndroidManifest.xml` | servicio tile + receiver + activity |
| `~/bin/screenrec.sh` | ADB, scrcpy, conversión MKV→MP4, MediaStore |
| `~/bin/qs-tap.sh` | helper de prueba |
| `build.sh` / `install.sh` | build, firma e instalación |
