#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT_DIR/dist/AmigaPS3Builder.app"
RES="$APP/Contents/Resources"

fail() {
  echo "verify-bundle: $1" >&2
  exit 1
}

[ -d "$APP" ] || fail "missing $APP — run ./scripts/build-app.sh first"

[ -f "$RES/Packager/make_pkg.exe" ] || [ -f "$RES/Packager/kit/psn_package_npdrm.exe" ] \
  || fail "Packager resources missing"

[ -f "$RES/Tutorial/CLIKAK500/USRDIR/EBOOT.BIN" ] || fail "Tutorial template missing"

[ -f "$RES/THIRD-PARTY-NOTICES.txt" ] || fail "THIRD-PARTY-NOTICES.txt missing"

arch=$(uname -m)
case "$arch" in
  arm64|aarch64)
    at3_bin="$RES/Tools/at3emu/aarch64/at3emu"
    atrac_bin="$RES/Tools/atracdenc/aarch64/atracdenc"
    ;;
  x86_64)
    at3_bin="$RES/Tools/at3emu/x86_64/at3emu"
    atrac_bin="$RES/Tools/atracdenc/x86_64/atracdenc"
    ;;
  *)
    at3_bin="$RES/Tools/at3emu/aarch64/at3emu"
    atrac_bin="$RES/Tools/atracdenc/aarch64/atracdenc"
    ;;
esac
if [ -x "$atrac_bin" ]; then
  echo "Bundled atracdenc: $(cat "$RES/Tools/atracdenc/atracdenc.version" 2>/dev/null || echo unknown)"
else
  echo "verify-bundle: no bundled atracdenc (AMIGA_SKIP_ATRACDENC build)"
fi
if [ -x "$at3_bin" ]; then
  echo "Bundled at3emu: $(cat "$RES/Tools/at3emu/at3emu.version" 2>/dev/null || echo unknown)"
else
  echo "verify-bundle: no bundled at3emu (AMIGA_SKIP_AT3EMU build)"
fi

if [ -f "$RES/Wine/wine/bin/wine" ]; then
  file "$RES/Wine/wine/bin/wine" | grep -Eq 'x86_64|i386' \
    || fail "bundled Wine is not an Intel binary"
  echo "Bundled Wine: $(cat "$RES/Wine/wine-runtime.version" 2>/dev/null || echo unknown)"
else
  echo "verify-bundle: no bundled Wine (AMIGA_SKIP_WINE build)"
fi

self_out=$("$APP/Contents/MacOS/AmigaPS3Builder" --self-test)
printf '%s\n' "$self_out"
printf '%s\n' "$self_out" | grep -q "SELF-TEST OK" || fail "self-test failed"
if [ -x "$atrac_bin" ]; then
  printf '%s\n' "$self_out" | grep -q "MUSIC-SELF-TEST OK" || fail "music conversion self-test failed"
fi

echo "verify-bundle: OK"
