#!/data/data/com.termux/files/usr/bin/bash
# build.sh - compila, empaqueta y firma el tile sin Gradle ni Android SDK
set -euo pipefail

cd "$(dirname "$0")"

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PATH"

ANDROID_JAR="android-36/android.jar"
MANIFEST="AndroidManifest.xml"
KEYSTORE="ks.jks"
KS_PASS="${KS_PASS:-android}"
KEY_PASS="${KEY_PASS:-android}"
KS_ALIAS="${KS_ALIAS:-k}"
OUT_APK="screenrec-tile.apk"
UNSIGNED="app-unsigned.apk"

# generar keystore de desarrollo si no existe (evita commitear secretos)
if [ ! -f "$KEYSTORE" ]; then
    echo "==> generando keystore de desarrollo ($KEYSTORE)"
    keytool -genkeypair -v \
        -keystore "$KEYSTORE" -alias "$KS_ALIAS" -keyalg RSA -keysize 2048 \
        -validity 10000 -storepass "$KS_PASS" -keypass "$KEY_PASS" \
        -dname "CN=ScreenTile,O=Local,C=AR" >/dev/null 2>&1
fi

echo "==> limpiando"
rm -rf classes dexout
mkdir -p classes dexout

echo "==> compilando java"
javac -source 8 -target 8 -Xlint:-options \
    -classpath "$ANDROID_JAR" \
    -d classes \
    $(find src -name '*.java')

echo "==> dex"
d8 --lib "$ANDROID_JAR" --min-api 24 \
    --output dexout \
    $(find classes -name '*.class')

echo "==> empaquetando recursos y manifest"
rm -f "$UNSIGNED" "$OUT_APK"
aapt2 link -o "$UNSIGNED" \
    --manifest "$MANIFEST" \
    -I "$ANDROID_JAR" \
    --min-sdk-version 24 \
    --target-sdk-version 35

echo "==> agregando classes.dex"
(cd dexout && jar uf "../$UNSIGNED" classes.dex)

echo "==> firmando"
apksigner sign \
    --ks "$KEYSTORE" \
    --ks-key-alias "$KS_ALIAS" \
    --ks-pass "pass:$KS_PASS" \
    --key-pass "pass:$KEY_PASS" \
    --out "$OUT_APK" \
    "$UNSIGNED"

apksigner verify --print-certs "$OUT_APK" | head -3
echo "==> listo: $OUT_APK"
