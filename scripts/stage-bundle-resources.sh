#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

APP_RESOURCES="${1:-$ROOT_DIR/dist/AmigaPS3Builder.app/Contents/Resources}"
TUTORIAL="$ROOT_DIR/Create Amiga PKG Tutorial"
if [ ! -f "$TUTORIAL/CLIKAK500/USRDIR/EBOOT.BIN" ]; then
  for candidate in \
    "$HOME/Downloads/Create Amiga PKG Tutorial" \
    "$HOME/projects/amiga-to-ps3/Create Amiga PKG Tutorial" \
    "/Applications/AmigaPS3Builder.app/Contents/Resources/Tutorial"
  do
    if [ -f "$candidate/CLIKAK500/USRDIR/EBOOT.BIN" ]; then
      TUTORIAL="$candidate"
      echo "Using tutorial assets from $TUTORIAL"
      break
    fi
  done
fi
MAKEPKG_RAR="$TUTORIAL/makepkg.rar"
FALLBACK_PACKAGER="/Applications/AmigaPS3Builder.app/Contents/Resources/Packager"

usage() {
  echo "Usage: $(basename "$0") [App/Contents/Resources]"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

mkdir -p "$APP_RESOURCES/Packager" "$APP_RESOURCES/Tutorial" "$APP_RESOURCES/Tools/at3emu" "$APP_RESOURCES/Tools/atracdenc"

ATRACDENC_VENDOR="$ROOT_DIR/vendor/atracdenc"
if [ -x "$ATRACDENC_VENDOR/aarch64/atracdenc" ] || [ -x "$ATRACDENC_VENDOR/x86_64/atracdenc" ] || [ -x "$ATRACDENC_VENDOR/atracdenc" ]; then
  echo "Copying staged atracdenc into Resources/Tools/atracdenc…"
  rm -rf "$APP_RESOURCES/Tools/atracdenc"
  mkdir -p "$APP_RESOURCES/Tools/atracdenc"
  cp -R "$ATRACDENC_VENDOR/." "$APP_RESOURCES/Tools/atracdenc/"
else
  echo "warning: no vendor/atracdenc — app will not include bundled atracdenc." >&2
  echo "         Run ./scripts/stage-atracdenc.sh" >&2
fi

AT3EMU_VENDOR="$ROOT_DIR/vendor/at3emu"
if [ -x "$AT3EMU_VENDOR/aarch64/at3emu" ] || [ -x "$AT3EMU_VENDOR/x86_64/at3emu" ] || [ -x "$AT3EMU_VENDOR/at3emu" ]; then
  echo "Copying staged at3emu into Resources/Tools/at3emu…"
  rm -rf "$APP_RESOURCES/Tools/at3emu"
  mkdir -p "$APP_RESOURCES/Tools/at3emu"
  cp -R "$AT3EMU_VENDOR/." "$APP_RESOURCES/Tools/at3emu/"
else
  echo "warning: no vendor/at3emu — app will not include bundled at3emu." >&2
  echo "         Run AMIGA_ALLOW_AT3EMU_FETCH=1 ./scripts/stage-at3emu.sh" >&2
fi

if [ -f "$MAKEPKG_RAR" ]; then
  echo "Extracting Windows packager into Resources/Packager…"
  rm -rf "$APP_RESOURCES/Packager"/*
  bsdtar -xf "$MAKEPKG_RAR" -C "$APP_RESOURCES/Packager"
elif [ -f "$FALLBACK_PACKAGER/kit/psn_package_npdrm.exe" ] || [ -f "$FALLBACK_PACKAGER/make_pkg.exe" ]; then
  echo "Copying Windows packager from $FALLBACK_PACKAGER…"
  rm -rf "$APP_RESOURCES/Packager"
  mkdir -p "$APP_RESOURCES/Packager"
  cp -R "$FALLBACK_PACKAGER/." "$APP_RESOURCES/Packager/"
else
  echo "error: missing $MAKEPKG_RAR and no fallback packager at $FALLBACK_PACKAGER" >&2
  exit 1
fi

if [ ! -f "$APP_RESOURCES/Packager/make_pkg.exe" ] && [ ! -f "$APP_RESOURCES/Packager/kit/psn_package_npdrm.exe" ]; then
  echo "error: makepkg.rar did not contain expected executables" >&2
  exit 1
fi

echo "Copying tutorial assets into Resources/Tutorial…"
rm -rf "$APP_RESOURCES/Tutorial"/*
for item in CLIKAK500 "trueancestor 1.80" "Icon,Wallpaper,Sound files for packages"; do
  if [ -e "$TUTORIAL/$item" ]; then
    cp -R "$TUTORIAL/$item" "$APP_RESOURCES/Tutorial/"
  fi
done

if [ ! -f "$APP_RESOURCES/Tutorial/CLIKAK500/USRDIR/EBOOT.BIN" ]; then
  echo "error: CLIKAK500 template missing from tutorial bundle" >&2
  exit 1
fi

WINE_VENDOR="$ROOT_DIR/vendor/wine-runtime"
if [ -d "$WINE_VENDOR/wine/bin" ]; then
  echo "Copying staged Wine runtime into Resources/Wine…"
  rm -rf "$APP_RESOURCES/Wine"
  mkdir -p "$APP_RESOURCES/Wine"
  cp -R "$WINE_VENDOR/wine" "$APP_RESOURCES/Wine/"
  if [ -d "$WINE_VENDOR/start" ]; then
    cp -R "$WINE_VENDOR/start" "$APP_RESOURCES/Wine/"
  fi
  cp "$WINE_VENDOR/wine-runtime.version" "$APP_RESOURCES/Wine/" 2>/dev/null || true
  cp "$ROOT_DIR/scripts/third-party-notices.txt" "$APP_RESOURCES/Wine/THIRD-PARTY-NOTICES.txt"
elif [ -x "/Applications/AmigaPS3Builder.app/Contents/Resources/Wine/wine/bin/wine" ]; then
  echo "Copying Wine runtime from /Applications/AmigaPS3Builder.app…"
  rm -rf "$APP_RESOURCES/Wine"
  mkdir -p "$APP_RESOURCES/Wine"
  cp -R "/Applications/AmigaPS3Builder.app/Contents/Resources/Wine/." "$APP_RESOURCES/Wine/"
else
  echo "warning: no vendor/wine-runtime — app will not include bundled Wine." >&2
  echo "         Run ./scripts/stage-wine-runtime.sh or AMIGA_SKIP_WINE=1 ./scripts/build-app.sh" >&2
fi

cp "$ROOT_DIR/scripts/third-party-notices.txt" "$APP_RESOURCES/THIRD-PARTY-NOTICES.txt"
echo "Bundled resources staged under $APP_RESOURCES"
