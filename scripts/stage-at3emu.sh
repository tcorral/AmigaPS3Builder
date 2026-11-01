#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

DEST_DIR="${1:-$ROOT_DIR/vendor/at3emu}"
MANIFEST="$ROOT_DIR/scripts/at3emu.manifest"
CACHE_DIR="$ROOT_DIR/vendor/at3emu-cache"

usage() {
  cat <<EOF
Usage: $(basename "$0") [destination-dir]

Stages at3emu macOS binaries for bundling into AmigaPS3Builder.app (ATRAC3 / SND0.AT3 encoding).

Output layout:
  \$DEST_DIR/aarch64/at3emu
  \$DEST_DIR/x86_64/at3emu
  \$DEST_DIR/at3emu.version

Environment:
  AMIGA_SKIP_AT3EMU=1       Skip staging and exit 0
  AMIGA_ALLOW_AT3EMU_FETCH=1  Download release assets from scripts/at3emu.manifest
  AT3EMU_DIR                Copy prebuilt tree that contains at3emu executable(s)
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "${AMIGA_SKIP_AT3EMU:-0}" = "1" ]; then
  echo "Skipping at3emu staging (AMIGA_SKIP_AT3EMU=1)."
  exit 0
fi

manifest_value() {
  key="$1"
  arch="$2"
  python3 - "$MANIFEST" "$arch" "$key" <<'PY'
import json, sys
path, arch, key = sys.argv[1:4]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
print(data["assets"][arch][key])
PY
}

stage_arch() {
  arch="$1"
  url=$(manifest_value url "$arch")
  sha=$(manifest_value sha256 "$arch")
  version=$(python3 - "$MANIFEST" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)["version"])
PY
)

  mkdir -p "$CACHE_DIR"
  archive="$CACHE_DIR/at3emu-${version}-${arch}-apple-darwin.tar.gz"
  if [ ! -f "$archive" ]; then
    echo "Downloading at3emu ${version} (${arch})…"
    curl -fsSL "$url" -o "$archive"
  fi
  echo "$sha  $archive" | shasum -a 256 -c -

  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT INT TERM
  tar -xzf "$archive" -C "$work"
  bin=$(find "$work" -maxdepth 2 -name at3emu -type f | head -n1)
  if [ -z "$bin" ]; then
    echo "error: at3emu binary not found in $archive" >&2
    exit 1
  fi
  mkdir -p "$DEST_DIR/$arch"
  cp "$bin" "$DEST_DIR/$arch/at3emu"
  chmod 755 "$DEST_DIR/$arch/at3emu"
  rm -rf "$work"
  trap - EXIT INT TERM
}

copy_local_tree() {
  src="$1"
  rm -rf "$DEST_DIR"
  mkdir -p "$DEST_DIR"
  if [ -f "$src/at3emu" ]; then
    mkdir -p "$DEST_DIR/$(uname -m)"
    cp "$src/at3emu" "$DEST_DIR/$(uname -m)/at3emu"
    chmod 755 "$DEST_DIR/$(uname -m)/at3emu"
  elif [ -f "$src/aarch64/at3emu" ] || [ -f "$src/x86_64/at3emu" ]; then
    cp -R "$src/." "$DEST_DIR/"
  else
    echo "error: AT3EMU_DIR must contain at3emu or arch subfolders" >&2
    exit 1
  fi
}

if [ -n "${AT3EMU_DIR:-}" ]; then
  copy_local_tree "$AT3EMU_DIR"
else
  if [ "${AMIGA_ALLOW_AT3EMU_FETCH:-0}" != "1" ]; then
    if [ -x "$DEST_DIR/aarch64/at3emu" ] && [ -x "$DEST_DIR/x86_64/at3emu" ]; then
      echo "at3emu already staged at $DEST_DIR"
      exit 0
    fi
    cat >&2 <<EOF
error: at3emu is not staged.

Run:
  AMIGA_ALLOW_AT3EMU_FETCH=1 ./scripts/stage-at3emu.sh

Or set AT3EMU_DIR to a folder with the at3emu binary.
EOF
    exit 1
  fi

  rm -rf "$DEST_DIR"
  mkdir -p "$DEST_DIR"
  stage_arch aarch64
  stage_arch x86_64
fi

version=$(python3 - "$MANIFEST" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)["version"])
PY
)
printf '%s\n' "$version" >"$DEST_DIR/at3emu.version"
echo "Staged at3emu at $DEST_DIR (version $version)."
