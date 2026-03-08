#!/usr/bin/env bash
# build-x86.sh — Build UML kernel for x86_64 (DevBox)
#
# MUST run on a native x86_64 host (ubuntu-24.04 runner).
# UML cannot be cross-compiled.
#
# Output: ./output/linux-uml-x86_64
#
# Usage:
#   ./scripts/build-x86.sh
#   UML_KERNEL_VERSION=6.12.74 ./scripts/build-x86.sh

set -euo pipefail

OUTPUT_DIR="$(pwd)/output"
UML_KERNEL_VERSION="${UML_KERNEL_VERSION:-6.12.74}"

mkdir -p "$OUTPUT_DIR"

log() { echo "[DevBox] $*"; }
die() { echo "[DevBox][ERROR] $*" >&2; exit 1; }

# ── Verify we are on x86_64 ─────────────────────────────────────────────────
HOST_ARCH="$(uname -m)"
[[ "$HOST_ARCH" != "x86_64" ]] && \
    die "build-x86.sh must run on x86_64. Current host: ${HOST_ARCH}"

# ── Download + extract kernel source ────────────────────────────────────────
MAJOR="${UML_KERNEL_VERSION%%.*}"
TARBALL="/tmp/linux-${UML_KERNEL_VERSION}.tar.xz"
SRC_DIR="/tmp/linux-${UML_KERNEL_VERSION}"

if [[ ! -d "$SRC_DIR" ]]; then
    if [[ ! -f "$TARBALL" ]]; then
        log "Downloading Linux ${UML_KERNEL_VERSION} source..."
        curl -L --fail --progress-bar \
            "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${UML_KERNEL_VERSION}.tar.xz" \
            -o "$TARBALL"
    fi
    log "Extracting..."
    tar -xf "$TARBALL" -C /tmp
fi

# ── Configure ────────────────────────────────────────────────────────────────
# x86_64 UML uses upstream defconfig — no custom port needed.
# We only append essential DevBox features on top.
BUILD_DIR="/tmp/linux-uml-x86_64"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

J="-j$(nproc)"

log "Configuring with defconfig..."
make -C "$SRC_DIR" O="$BUILD_DIR" ARCH=um defconfig $J

# Append essential UML features not in upstream x86_64 defconfig
cat >> "$BUILD_DIR/.config" <<'KCONFIG'
CONFIG_HOSTFS=y
CONFIG_UML_NET_SLIRP=y
CONFIG_BLK_DEV_UBD=y
CONFIG_EXT4_FS=y
CONFIG_EXT4_USE_FOR_EXT2=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_NET=y
CONFIG_INET=y
CONFIG_UNIX=y
CONFIG_PACKET=y
CONFIG_UML_NET=y
CONFIG_UNIX98_PTYS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
KCONFIG

make -C "$SRC_DIR" O="$BUILD_DIR" ARCH=um olddefconfig

# ── Compile ──────────────────────────────────────────────────────────────────
log "Compiling UML kernel (~5 min)..."
make -C "$SRC_DIR" O="$BUILD_DIR" ARCH=um $J

# ── Copy output ──────────────────────────────────────────────────────────────
UML_BIN=$(find "$BUILD_DIR" -maxdepth 1 \( -name "linux" -o -name "vmlinux" \) 2>/dev/null | head -1)
[[ -z "$UML_BIN" ]] && die "UML binary not found after build"

DEST="$OUTPUT_DIR/linux-uml-x86_64"
cp "$UML_BIN" "$DEST"
chmod +x "$DEST"
log "Done: linux-uml-x86_64 ($(du -sh "$DEST" | cut -f1))"
