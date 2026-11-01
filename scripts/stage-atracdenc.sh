#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

DEST_DIR="${1:-$ROOT_DIR/vendor/atracdenc}"
MANIFEST="$ROOT_DIR/scripts/atracdenc.manifest"
SRC_DIR="$ROOT_DIR/vendor/atracdenc-src"

usage() {
  cat <<EOF
Usage: $(basename "$0") [destination-dir]

Builds atracdenc-rs and stages macOS binaries for bundling (ATRAC3 / SND0.AT3).

Output layout:
  \$DEST_DIR/aarch64/atracdenc
  \$DEST_DIR/x86_64/atracdenc   (when the x86_64-apple-darwin target is installed)
  \$DEST_DIR/atracdenc.version
  \$DEST_DIR/LICENSE

Environment:
  AMIGA_SKIP_ATRACDENC=1     Skip staging and exit 0
  ATRACDENC_DIR              Copy a prebuilt tree that contains atracdenc
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "${AMIGA_SKIP_ATRACDENC:-0}" = "1" ]; then
  echo "Skipping atracdenc staging (AMIGA_SKIP_ATRACDENC=1)."
  exit 0
fi

manifest_value() {
  python3 - "$MANIFEST" "$1" <<'PY'
import json, sys
path, key = sys.argv[1:3]
with open(path, encoding="utf-8") as f:
    print(json.load(f)[key])
PY
}

host_arch_folder() {
  case "$(uname -m)" in
    arm64|aarch64) echo aarch64 ;;
    x86_64) echo x86_64 ;;
    *) uname -m ;;
  esac
}

copy_local_tree() {
  src="$1"
  rm -rf "$DEST_DIR"
  mkdir -p "$DEST_DIR"
  if [ -f "$src/atracdenc" ]; then
    mkdir -p "$DEST_DIR/$(host_arch_folder)"
    cp "$src/atracdenc" "$DEST_DIR/$(host_arch_folder)/atracdenc"
    chmod 755 "$DEST_DIR/$(host_arch_folder)/atracdenc"
  elif [ -f "$src/aarch64/atracdenc" ] || [ -f "$src/x86_64/atracdenc" ]; then
    cp -R "$src/." "$DEST_DIR/"
  else
    echo "error: ATRACDENC_DIR must contain atracdenc or arch subfolders" >&2
    exit 1
  fi
}

already_staged() {
  [ -x "$DEST_DIR/aarch64/atracdenc" ] || [ -x "$DEST_DIR/x86_64/atracdenc" ] || [ -x "$DEST_DIR/atracdenc" ]
}

if [ -n "${ATRACDENC_DIR:-}" ]; then
  copy_local_tree "$ATRACDENC_DIR"
elif already_staged; then
  echo "atracdenc already staged at $DEST_DIR"
  exit 0
else
  if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
    echo "error: cargo is required to build atracdenc-rs. Install Rust from https://rustup.rs" >&2
    exit 1
  fi
  rustc_ok=$(python3 - <<'PY'
import subprocess, sys
text = subprocess.check_output(["rustc", "--version"], text=True)
version = text.split()[1]
parts = [int(p) for p in version.split(".")[:2]]
print("yes" if tuple(parts) >= (1, 88) else "no")
PY
)
  if [ "$rustc_ok" != "yes" ]; then
    echo "error: atracdenc-rs needs rustc 1.88 or newer (found $(rustc --version))." >&2
    echo "       Run: rustup update stable" >&2
    exit 1
  fi

  git_url=$(manifest_value git_url)
  git_ref=$(manifest_value git_ref)
  version=$(manifest_value version)

  if [ ! -d "$SRC_DIR/.git" ]; then
    echo "Fetching atracdenc-rs ${git_ref}…"
    rm -rf "$SRC_DIR"
    git clone --depth 1 --branch "$git_ref" "$git_url" "$SRC_DIR"
  else
    git -C "$SRC_DIR" fetch --depth 1 origin "$git_ref"
    git -C "$SRC_DIR" checkout --detach FETCH_HEAD
  fi

  echo "Building atracdenc-rs ${version} for $(uname -m)…"
  cargo build --release -p atracdenc-cli --manifest-path "$SRC_DIR/Cargo.toml"

  host_bin="$SRC_DIR/target/release/atracdenc"
  if [ ! -x "$host_bin" ]; then
    echo "error: cargo did not produce $host_bin" >&2
    exit 1
  fi

  rm -rf "$DEST_DIR"
  mkdir -p "$DEST_DIR/$(host_arch_folder)"
  cp "$host_bin" "$DEST_DIR/$(host_arch_folder)/atracdenc"
  chmod 755 "$DEST_DIR/$(host_arch_folder)/atracdenc"

  if rustup target list --installed 2>/dev/null | grep -qx 'x86_64-apple-darwin' \
    && [ "$(uname -m)" != "x86_64" ]; then
    echo "Building atracdenc-rs ${version} for x86_64…"
    if cargo build --release -p atracdenc-cli --target x86_64-apple-darwin --manifest-path "$SRC_DIR/Cargo.toml"; then
      mkdir -p "$DEST_DIR/x86_64"
      cp "$SRC_DIR/target/x86_64-apple-darwin/release/atracdenc" "$DEST_DIR/x86_64/atracdenc"
      chmod 755 "$DEST_DIR/x86_64/atracdenc"
    else
      echo "warning: x86_64 atracdenc build failed; continuing with host binary only." >&2
    fi
  fi

  if [ -f "$SRC_DIR/LICENSE" ]; then
    cp "$SRC_DIR/LICENSE" "$DEST_DIR/LICENSE"
  elif [ -f "$SRC_DIR/COPYING" ]; then
    cp "$SRC_DIR/COPYING" "$DEST_DIR/LICENSE"
  fi
fi

version=$(manifest_value version)
printf '%s\n' "$version" >"$DEST_DIR/atracdenc.version"
echo "Staged atracdenc at $DEST_DIR (version $version)."
