#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

REQUIRE_WINE="${AMIGA_REQUIRE_WINE:-1}"
REQUIRE_AT3EMU="${AMIGA_REQUIRE_AT3EMU:-1}"
REQUIRE_ATRACDENC="${AMIGA_REQUIRE_ATRACDENC:-1}"

if [ "$REQUIRE_ATRACDENC" = "1" ] && [ "${AMIGA_SKIP_ATRACDENC:-0}" != "1" ]; then
  if [ ! -x "$ROOT_DIR/vendor/atracdenc/aarch64/atracdenc" ] && [ ! -x "$ROOT_DIR/vendor/atracdenc/x86_64/atracdenc" ]; then
    echo "atracdenc not staged; running scripts/stage-atracdenc.sh…"
    ./scripts/stage-atracdenc.sh "$ROOT_DIR/vendor/atracdenc"
  fi
fi

if [ "$REQUIRE_AT3EMU" = "1" ] && [ "${AMIGA_SKIP_AT3EMU:-0}" != "1" ]; then
  if [ ! -x "$ROOT_DIR/vendor/at3emu/aarch64/at3emu" ] || [ ! -x "$ROOT_DIR/vendor/at3emu/x86_64/at3emu" ]; then
    echo "at3emu not staged; running scripts/stage-at3emu.sh…"
    AMIGA_ALLOW_AT3EMU_FETCH=1 ./scripts/stage-at3emu.sh "$ROOT_DIR/vendor/at3emu"
  fi
fi

if [ "$REQUIRE_WINE" = "1" ] && [ "${AMIGA_SKIP_WINE:-0}" != "1" ]; then
  if [ ! -f "$ROOT_DIR/vendor/wine-runtime/wine/bin/wine" ]; then
    echo "Wine runtime not staged; running scripts/stage-wine-runtime.sh…"
    ./scripts/stage-wine-runtime.sh "$ROOT_DIR/vendor/wine-runtime"
  fi
fi

swift build -c release

APP_DIR="$ROOT_DIR/dist/AmigaPS3Builder.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/AmigaPS3Builder" "$APP_DIR/Contents/MacOS/AmigaPS3Builder"
cp "$ROOT_DIR/scripts/Info.plist" "$APP_DIR/Contents/Info.plist"

if [ ! -f "$ROOT_DIR/scripts/AppIcon.icns" ]; then
  echo "App icon missing; run ./scripts/generate-app-icon.sh" >&2
  exit 1
fi
cp "$ROOT_DIR/scripts/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

./scripts/stage-bundle-resources.sh "$APP_DIR/Contents/Resources"

if [ "$REQUIRE_ATRACDENC" = "1" ] && [ "${AMIGA_SKIP_ATRACDENC:-0}" != "1" ]; then
  arch=$(uname -m)
  case "$arch" in
    arm64|aarch64) atrac_bin="$APP_DIR/Contents/Resources/Tools/atracdenc/aarch64/atracdenc" ;;
    x86_64) atrac_bin="$APP_DIR/Contents/Resources/Tools/atracdenc/x86_64/atracdenc" ;;
    *) atrac_bin="$APP_DIR/Contents/Resources/Tools/atracdenc/aarch64/atracdenc" ;;
  esac
  if [ ! -x "$atrac_bin" ]; then
    cat >&2 <<EOF
error: release app is missing bundled atracdenc for $arch.

Stage atracdenc first:
  ./scripts/stage-atracdenc.sh

Or build without atracdenc:
  AMIGA_SKIP_ATRACDENC=1 AMIGA_REQUIRE_ATRACDENC=0 ./scripts/build-app.sh
EOF
    exit 1
  fi
fi

if [ "$REQUIRE_AT3EMU" = "1" ] && [ "${AMIGA_SKIP_AT3EMU:-0}" != "1" ]; then
  arch=$(uname -m)
  case "$arch" in
    arm64) at3_bin="$APP_DIR/Contents/Resources/Tools/at3emu/aarch64/at3emu" ;;
    x86_64) at3_bin="$APP_DIR/Contents/Resources/Tools/at3emu/x86_64/at3emu" ;;
    *) at3_bin="$APP_DIR/Contents/Resources/Tools/at3emu/aarch64/at3emu" ;;
  esac
  if [ ! -x "$at3_bin" ]; then
    cat >&2 <<EOF
error: release app is missing bundled at3emu for $arch.

Stage at3emu first:
  AMIGA_ALLOW_AT3EMU_FETCH=1 ./scripts/stage-at3emu.sh

Or build without at3emu:
  AMIGA_SKIP_AT3EMU=1 AMIGA_REQUIRE_AT3EMU=0 ./scripts/build-app.sh
EOF
    exit 1
  fi
fi

if [ "$REQUIRE_WINE" = "1" ] && [ "${AMIGA_SKIP_WINE:-0}" != "1" ]; then
  if [ ! -f "$APP_DIR/Contents/Resources/Wine/wine/bin/wine" ]; then
    cat >&2 <<EOF
error: release app is missing bundled Wine.

Stage Wine first:
  AMIGA_ALLOW_WINE_FETCH=1 ./scripts/stage-wine-runtime.sh
or set WINE_RUNTIME_DIR=/Applications/Wine\\ Stable.app

Or build without Wine (Prepare files only):
  AMIGA_SKIP_WINE=1 AMIGA_REQUIRE_WINE=0 ./scripts/build-app.sh
EOF
    exit 1
  fi
fi

echo "Created $APP_DIR"
