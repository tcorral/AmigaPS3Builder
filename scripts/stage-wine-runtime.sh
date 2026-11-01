#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

DEST_DIR="${1:-$ROOT_DIR/vendor/wine-runtime}"
MANIFEST="$ROOT_DIR/scripts/wine-runtime.manifest"
CACHE_DIR="$ROOT_DIR/vendor/wine-cache"

usage() {
  cat <<EOF
Usage: $(basename "$0") [destination-dir]

Stages a WineHQ macOS x86_64 runtime for bundling into AmigaPS3Builder.app.

Sources (first match wins):
  1. WINE_RUNTIME_DIR — directory containing wine/bin/wine (or Wine Stable.app)
  2. /Applications/Wine Stable.app
  3. Download from scripts/wine-runtime.manifest (requires curl, shasum, bsdtar)

Output layout:
  \$DEST_DIR/wine/bin/wine
  \$DEST_DIR/wine-runtime.version

Environment:
  AMIGA_SKIP_WINE=1     Skip staging and exit 0 (packager-only bundle)
  AMIGA_ALLOW_WINE_FETCH=1  Allow downloading the manifest URL
EOF
}

if [ "${AMIGA_SKIP_WINE:-0}" = "1" ]; then
  echo "Skipping Wine runtime staging (AMIGA_SKIP_WINE=1)."
  exit 0
fi

copy_wine_tree() {
  src_root="$1"
  rm -rf "$DEST_DIR"
  mkdir -p "$DEST_DIR"

  if [ -f "$src_root/wine/bin/wine" ]; then
    mkdir -p "$DEST_DIR/wine"
    cp -R "$src_root/wine/." "$DEST_DIR/wine/"
  elif [ -d "$src_root/Contents/Resources/wine/bin/wine" ] || [ -f "$src_root/Contents/Resources/wine/bin/wine" ]; then
    mkdir -p "$DEST_DIR/wine"
    cp -R "$src_root/Contents/Resources/wine/." "$DEST_DIR/wine/"
    if [ -d "$src_root/Contents/Resources/start" ]; then
      mkdir -p "$DEST_DIR/start"
      cp -R "$src_root/Contents/Resources/start/." "$DEST_DIR/start/"
    fi
  else
    echo "error: could not find wine/bin/wine under $src_root" >&2
    return 1
  fi

  if [ ! -f "$DEST_DIR/wine/bin/wine" ]; then
    echo "error: staged Wine binary missing at $DEST_DIR/wine/bin/wine" >&2
    return 1
  fi

  file "$DEST_DIR/wine/bin/wine" | grep -q 'x86_64' || {
    echo "warning: Wine binary is not x86_64; Apple Silicon builds expect an Intel Wine build." >&2
  }

  version="${WINE_RUNTIME_VERSION:-unknown}"
  if [ -f "$MANIFEST" ]; then
    version=$(grep '"version"' "$MANIFEST" | head -n1 | tr -d '\r' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    version=${version:-unknown}
  fi
  printf '%s\n' "$version" >"$DEST_DIR/wine-runtime.version"
  cp "$ROOT_DIR/scripts/third-party-notices.txt" "$DEST_DIR/THIRD-PARTY-NOTICES.txt"
  echo "Staged Wine runtime at $DEST_DIR (version $version)."
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ -n "${WINE_RUNTIME_DIR:-}" ]; then
  copy_wine_tree "$WINE_RUNTIME_DIR"
  exit 0
fi

if [ -d "/Applications/Wine Stable.app" ]; then
  copy_wine_tree "/Applications/Wine Stable.app"
  exit 0
fi

if [ "${AMIGA_ALLOW_WINE_FETCH:-0}" != "1" ]; then
  cat >&2 <<EOF
error: no Wine runtime found.

Install Wine Stable to /Applications, set WINE_RUNTIME_DIR, or run:
  AMIGA_ALLOW_WINE_FETCH=1 ./scripts/stage-wine-runtime.sh

To build the app without Wine (Prepare files only), use:
  AMIGA_SKIP_WINE=1 ./scripts/build-app.sh
EOF
  exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "error: curl required to download Wine" >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "error: shasum required" >&2; exit 1; }
command -v bsdtar >/dev/null 2>&1 || { echo "error: bsdtar required" >&2; exit 1; }

url=$(grep '"url"' "$MANIFEST" | head -n1 | tr -d '\r' | sed 's/.*"\(https[^"]*\)".*/\1/')
sha=$(grep '"sha256"' "$MANIFEST" | head -n1 | tr -d '\r' | sed 's/.*"\([a-f0-9]*\)".*/\1/')
version=$(grep '"version"' "$MANIFEST" | head -n1 | tr -d '\r' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
version=${version:-unknown}

mkdir -p "$CACHE_DIR"
archive="$CACHE_DIR/wine-stable-${version}-osx64.tar.xz"
if [ ! -f "$archive" ]; then
  echo "Downloading Wine ${version}..."
  curl -fsSL "$url" -o "$archive"
fi
echo "$sha  $archive" | shasum -a 256 -c -

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
bsdtar -xf "$archive" -C "$work"

app_path=$(find "$work" -maxdepth 2 -name 'Wine Stable.app' -print | head -n1)
if [ -n "$app_path" ]; then
  copy_wine_tree "$app_path"
else
  copy_wine_tree "$work"
fi
