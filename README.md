# Grabar pantalla con scrcpy desde el propio teléfono

Aplicación Quick Settings (Centro de control) llamada **Grabar pantalla** que permite grabar la pantalla del mismo dispositivo sin root. El tile es un control remoto: dispara `~/bin/screenrec.sh`, que corre `scrcpy` conectado por TCP a `127.0.0.1:5555` (o al puerto detectado por el sistema).

## Qué incluye el repositorio

- `~/bin/screenrec.sh` — grabación con `scrcpy`, conversión MKV → MP4 y aviso al MediaStore.
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
- **Termux instalado desde F-Droid**: <https://f-droid.org/packages/com.termux/>
  (la versión de Play Store está desactualizada y puede fallar con `RUN_COMMAND`).
- Termux instalado y actualizado (`pkg update -y && pkg upgrade -y`)
- Termux con **acceso externo habilitado**: en `~/.termux/termux.properties` escribir
  `allow-external-apps = true` y reiniciar Termux.
- Permiso de almacenamiento de Termux (necesario para escribir en `/sdcard/DCIM/ScreenRecorder`):

  ```bash
  termux-setup-storage
  ```

  Acepta el diálogo de Android. Verifica con:

  ```bash
  ls ~/storage/shared/DCIM
  ```
- Dependencias en Termux. `scrcpy` está en el repositorio **x11**, que se habilita con el paquete `x11-repo`:

  ```bash
  pkg update -y
  pkg install -y x11-repo
  pkg update -y
  pkg install -y scrcpy ffmpeg android-tools
  ```

  > `termux-change-repo` sirve para elegir un **mirror**, no para habilitar repositorios. `x11-repo` es la forma oficial de agregar el repositorio x11. Si instalaste `scrcpy` desde un `.deb` manual, funciona, pero no recibe actualizaciones; mejor usar `pkg install scrcpy`.

- ADB disponible por TCP (local) para que `scrcpy` pueda capturar la pantalla:
  - Verificar con `adb devices`.
  - Si no aparece `127.0.0.1:5555 device`, habilitar ADB por TCP con alguno de estos métodos:

    **Método A (si el ROM ya lo expone, como muchos MIUI/Xiaomi):**
    no hace falta hacer nada.

    **Método B (con root, desde Termux):**
    ```bash
    tsu -c "setprop service.adb.tcp.port 5555; stop adbd; start adbd"
    ```

    **Método C (desde USB/ADB en una PC):**
    ```bash
    adb devices
    adb tcpip 5555
    adb connect 127.0.0.1:5555
    ```

    **Método D (Android 11+ emparejamiento inalámbrico):**
    usar `adb pair` y `adb connect`, luego exportar `SERIAL` con el puerto asignado:
    ```bash
    SERIAL=127.0.0.1:<puerto> ~/bin/screenrec.sh start
    ```
  - Si tu dispositivo usa un puerto distinto de 5555, redefine `SERIAL` por entorno.
- El tile necesita permiso `com.termux.permission.RUN_COMMAND` (otorgado por `install.sh`).

## Instalación paso a paso

> Antes de empezar, instala Termux desde F-Droid: <https://f-droid.org/packages/com.termux/>

1. Prepara Termux (actualiza todo, dependencias y PATH):

   ```bash
   pkg update -y && pkg upgrade -y
   # opcional: elegir un mirror con termux-change-repo
   pkg install -y x11-repo
   pkg update -y
   pkg install -y scrcpy ffmpeg android-tools
   termux-setup-storage     # aceptar el permiso de almacenamiento
   mkdir -p ~/bin
   grep -q 'export PATH="$HOME/bin:$PATH"' ~/.bashrc || \
       echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

2. Clona/copiá el proyecto:

   ```bash
   git clone https://github.com/jose-alejandro-loaiza-lopez/screenrec-termux.git ~/projects/screenrec
   cd ~/projects/screenrec
   ```

3. Compila y firma:

   ```bash
   ./build.sh
   ```

   (Si falta `ks.jks`, `build.sh` lo genera con clave de desarrollo.)

4. Instala y concede permiso:

   ```bash
   ./install.sh
   ```

5. Agrega el tile **Grabar pantalla** al Centro de control (editor de tiles, si no aparece solo).

6. Prueba:

   ```bash
   ~/bin/screenrec.sh start
   # graba unos segundos
   ~/bin/screenrec.sh stop
   ls -lh /sdcard/DCIM/ScreenRecorder
   ```

Rebuild / reinstall manual:

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
| `build.sh` / `install.sh` | build, firma e instalación |
