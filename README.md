# Grabar pantalla con scrcpy desde el propio teléfono

Aplicación Quick Settings (Centro de control) llamada **Grabar pantalla** que permite grabar la pantalla del mismo dispositivo sin root. El tile es un control remoto: dispara `~/bin/screenrec.sh`, que corre `scrcpy` conectado por TCP a `127.0.0.1:5555` (o al puerto detectado por el sistema).

## Por qué existe este proyecto

El grabador de pantalla integrado en MIUI/HyperOS (Xiaomi/POCO) puede tener limitaciones. Este proyecto ofrece una mayor calidad, control y rendimiento usando **scrcpy**, mientras el tile solo actúa como control remoto.

- `~/bin/screenrec.sh` — grabación con `scrcpy`, conversión MKV → MP4 y aviso al MediaStore.
- `dev.local.screentile` (`screenrec-tile.apk`) — tile en el Centro de control + app de configuración.
- Fuentes Java en `src/dev/local/screentile/`.
- `build.sh` / `install.sh` — compilación, firma e instalación automatizadas (install.sh también copia `scripts/` a `~/bin`).
- `scripts/screenrec.sh` — script de Termux versionado en el repo.
- `scripts/screenrec-cleanup.sh` — limpia las herramientas de compilación después de instalar.
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
  - Fuente de audio: interno (por defecto) / micrófono / interno + micrófono / sin audio
  - Bitrate de audio: 128 / 256 / 320 kbps
- Grabación en `.mkv`, conversión automática a `.mp4` (H.264/H.265 + AAC) y borrado del `.mkv`.
- Con audio interno, el sonido sigue saliendo por el teléfono (`--audio-dup`).
- La opción **interno + micrófono** usa `voice-performance` de scrcpy.
- Resolución calculada dinámicamente según las dimensiones reales del display.
- Aviso al MediaStore para que Galería/Fotos/Telegram detecten el `.mp4`.
- Sin root ni modificaciones del sistema (todo en `/data`).

## Cómo funciona

1. El tile envía `com.termux.RUN_COMMAND` a Termux.
2. `screenrec.sh` ejecuta `ensure_adb()` (connect a `127.0.0.1:$PORT` o al puerto detectado).
3. Lanza `scrcpy` con `setsid`, `--max-size`, `--min-size-alignment=8` y la fuente de audio elegida (`playback` + `--audio-dup`, `mic`, `voice-performance` o `--no-audio`).
4. Al detener envía `SIGINT` a scrcpy (flush correcto del archivo).
5. Convierte el `.mkv` a `.mp4` con `ffmpeg` (`-c:v copy`, AAC si hay audio, `+faststart`, tag `hvc1` en H.265).
6. Notifica al MediaStore y envía broadcast `dev.local.screentile.STATE` para actualizar el tile.

## Requisitos y preparación del entorno

> **Completa toda esta sección antes de empezar la instalación paso a paso.**
> La instalación asume que Termux, las dependencias, el acceso al almacenamiento y ADB ya están listos.

### 1. Instalar Termux desde F-Droid

- Android 7 o superior.
- Instala Termux desde F-Droid: <https://f-droid.org/packages/com.termux/>
- No uses la versión de Play Store: está desactualizada y puede fallar con `RUN_COMMAND`.

Abre Termux y actualiza todos los paquetes:

```bash
pkg update -y && pkg upgrade -y
```

### 2. Habilitar el repositorio x11

`scrcpy` está en el repositorio **x11**, que se habilita con el paquete `x11-repo`:

```bash
pkg install -y x11-repo
pkg update -y
```

> `termux-change-repo` solo cambia el mirror; no habilita repositorios.

### 3. Instalar dependencias

```bash
pkg install -y scrcpy ffmpeg android-tools git \
  openjdk-17 d8 aapt2 apksigner
```

Verifica que estén disponibles:

```bash
pkg show scrcpy
command -v javac d8 aapt2 apksigner git adb ffmpeg
```

> Si `scrcpy` no aparece, revisa que `x11-repo` se haya instalado y ejecuta `pkg update -y` otra vez.

### 4. Dar acceso al almacenamiento

Necesario para escribir en `/sdcard/DCIM/ScreenRecorder`:

```bash
termux-setup-storage
```

Acepta el diálogo de Android y verifica:

```bash
ls ~/storage/shared/DCIM
```

### 5. Permitir comandos externos

El tile ejecuta comandos dentro de Termux, así que hay que habilitar `allow-external-apps` en `~/.termux/termux.properties`. Por defecto esa opción viene comentada (`# allow-external-apps = true`), así que el comando la descomenta si existe o la agrega si no está:

```bash
mkdir -p ~/.termux
touch ~/.termux/termux.properties
sed -i 's/^[[:space:]]*#\{0,1\}[[:space:]]*allow-external-apps[[:space:]]*=.*/allow-external-apps = true/' \
  ~/.termux/termux.properties
grep -q '^allow-external-apps[[:space:]]*=[[:space:]]*true' ~/.termux/termux.properties || \
  echo 'allow-external-apps = true' >> ~/.termux/termux.properties
termux-reload-settings
```

### 6. Activar opciones de desarrollador e "Instalar vía USB"

1. Activa las opciones de desarrollador: Ajustes → Acerca del teléfono → toca 7 veces **Número de compilación**.
2. Entra en Ajustes → Sistema → **Opciones de desarrollador** y activa:
   - **Depuración USB**.
   - **Instalar vía USB** (en MIUI/HyperOS puede aparecer como **Instalar vía USB (Ajustes de seguridad)**). Sin esto, `adb install` puede fallar con `INSTALL_FAILED_USER_RESTRICTED`.
   - **Depuración inalámbrica** solo si vas a usar el método D de abajo.
3. En MIUI/HyperOS puede pedir iniciar sesión con la cuenta Mi y reiniciar. Acepta y vuelve a comprobar que las tres opciones sigan activas.

### 7. Preparar ADB por TCP

`scrcpy` necesita ADB local. Comprueba primero:

```bash
adb connect 127.0.0.1:5555 >/dev/null 2>&1 || true
adb devices
```

Debe aparecer `127.0.0.1:5555    device`. Si no aparece, usa uno de estos métodos:

**Método A (el ROM ya expone ADB por TCP, como muchos MIUI/Xiaomi):**
no hace falta hacer nada más.

**Método B (con root, desde Termux):**

```bash
pkg install -y tsu
tsu -c "setprop service.adb.tcp.port 5555; stop adbd; start adbd"
```

**Método C (desde una PC con USB):**

```bash
# con el teléfono conectado por USB y depuración USB activa
adb devices
adb tcpip 5555
```

Desconecta el USB y, en Termux del teléfono:

```bash
adb connect 127.0.0.1:5555
adb devices
```

**Método D (emparejamiento inalámbrico de Android 11+):**

```bash
adb pair 127.0.0.1:<puerto-de-emparejamiento>
adb connect 127.0.0.1:<puerto-de-conexion>
```

> Si el puerto no es 5555, el script intenta leer `service.adb.tcp.port`; también puedes forzarlo con `SERIAL=127.0.0.1:PUERTO`.

El permiso `com.termux.permission.RUN_COMMAND` no se concede a mano: lo otorga `install.sh` durante la instalación.

## Instalación paso a paso

> **Antes de empezar:** completa la sección **Requisitos y preparación del entorno**. La instalación no repite esos comandos; solo asume que ya están hechos.

1. Clona el proyecto:

   ```bash
   git clone https://github.com/jose-alejandro-loaiza-lopez/screenrec-termux.git ~/projects/screenrec
   cd ~/projects/screenrec
   ```

2. Compila y firma:

   ```bash
   ./build.sh
   ```

   (Si falta `ks.jks`, `build.sh` lo genera con clave de desarrollo.)

3. Instala y concede el permiso `RUN_COMMAND`:

   ```bash
   ./install.sh
   ```

   `install.sh` también copia `screenrec.sh` a `~/bin` y agrega esa carpeta al `PATH`.

   Si falla con `INSTALL_FAILED_USER_RESTRICTED`, activa **Instalar vía USB** en Opciones de desarrollador (ver paso 6 de los requisitos).

4. Agrega el tile **Grabar pantalla** al Centro de control (editor de tiles, si no aparece solo).

5. Prueba:

   ```bash
   ~/bin/screenrec.sh start
   # graba unos segundos
   ~/bin/screenrec.sh stop
   ls -lh /sdcard/DCIM/ScreenRecorder
   ```

### Rebuild (solo si modificas el código)

```bash
cd ~/projects/screenrec
./build.sh
adb -s 127.0.0.1:5555 install -r screenrec-tile.apk
adb -s 127.0.0.1:5555 shell pm grant dev.local.screentile com.termux.permission.RUN_COMMAND
```

## Liberar espacio después de instalar

Una vez compilada e instalada la app, las herramientas de compilación (git, JDK, d8, aapt2, apksigner) ya no son necesarias para usarla.

El comando queda disponible después de `install.sh`:

```bash
# ver qué eliminaría, sin tocar nada
screenrec-cleanup --dry-run

# eliminar, pidiendo confirmación
screenrec-cleanup

# eliminar sin preguntar
screenrec-cleanup --yes
```

(Si el comando no se reconoce, ejecuta `source ~/.bashrc` o usa `~/bin/screenrec-cleanup`.)

El comando elimina esas herramientas, dependencias huerfanas y la cache de paquetes de Termux. Conserva `scrcpy`, `ffmpeg`, `android-tools` y `x11-repo`.

Si más tarde modificas el código y quieres recompilar, reinstala las dependencias de compilación:

```bash
pkg install -y git openjdk-17 d8 aapt2 apksigner
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
MAX_SIZE=2400 MAX_FPS=60 VCODEC=h264 BITRATE=0 ABITRATE=128K ASOURCE=playback \
  ~/bin/screenrec.sh start
```

También se pueden pasar posicionalmente:

```bash
~/bin/screenrec.sh start <max-size> <fps> <codec> <video-mbps> <audio-kbps> <audio-source>
```

Valores de `<audio-source>`:

| Valor | Fuente |
|---|---|
| `playback` | Audio interno, por defecto |
| `mic` | Micrófono |
| `both` | Interno + micrófono (`voice-performance`) |
| `none` | Sin audio |

Notas de audio:

- **Interno**: captura el audio de las apps y, con `--audio-dup`, sigue sonando por el teléfono.
- **Micrófono**: usa la fuente `mic` de scrcpy.
- **Interno + micrófono**: scrcpy usa `voice-performance`, que mezcla micrófono y reproducción del dispositivo. La disponibilidad depende del fabricante.
- **Sin audio**: graba solo video; la conversión a MP4 no agrega pista AAC.

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
