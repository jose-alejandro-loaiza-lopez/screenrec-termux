#!/data/data/com.termux/files/usr/bin/bash
# qs-tap.sh "<desc>" - abre el panel de control y toca el tile con ese content-desc
set -u
export PATH=/data/data/com.termux/files/usr/bin:$PATH
DESC="${1:?falta descripcion}"
cmd statusbar expand-settings >/dev/null 2>&1
sleep 1.5
uiautomator dump /sdcard/_qs_tap.xml >/dev/null 2>&1
COORDS=$(python3 - "$DESC" <<'EOF'
import re, sys
want = sys.argv[1]
s = open('/sdcard/_qs_tap.xml', encoding='utf-8', errors='ignore').read()
for m in re.finditer(r'<node[^>]*>', s):
    n = m.group(0)
    if re.search(r'content-desc="([^"]*)"', n).group(1) != want:
        continue
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    if b:
        print((int(b.group(1)) + int(b.group(3))) // 2, (int(b.group(2)) + int(b.group(4))) // 2)
        break
EOF
)
if [ -z "$COORDS" ]; then
    echo "tile no encontrado: $DESC" >&2
    exit 1
fi
set -- $COORDS
echo "tap $1 $2 ($DESC)"
input tap "$1" "$2"
