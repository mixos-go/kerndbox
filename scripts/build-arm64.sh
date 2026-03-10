#!/usr/bin/env bash
# build-arm64.sh — Build UML kernel for arm64 (DevBox)
#
# MUST run on a native aarch64 host (debian:bookworm container (ubuntu-24.04-arm runner)).
# UML cannot be cross-compiled.
#
# Output: ./output/kernel-arm64
#
# Usage:
#   ./scripts/build-arm64.sh
#   UML_KERNEL_VERSION=6.12.74 ./scripts/build-arm64.sh

set -euo pipefail

OUTPUT_DIR="$(pwd)/output"
BUILD_LOG="$OUTPUT_DIR/build-arm64.log"
UML_KERNEL_VERSION="${UML_KERNEL_VERSION:-6.12.74}"

mkdir -p "$OUTPUT_DIR"

# Tee all output (stdout + stderr) to build log on host output/
exec > >(tee -a "$BUILD_LOG") 2>&1
echo "[build] Log: $BUILD_LOG"
echo "[build] Started: $(date '+%Y-%m-%d %H:%M:%S')"

log() { echo "[DevBox] $*"; }
die() { echo "[DevBox][ERROR] $*" >&2; exit 1; }

# ── Verify we are on aarch64 ────────────────────────────────────────────────
HOST_ARCH="$(uname -m)"
[[ "$HOST_ARCH" == "arm64" ]] && HOST_ARCH="aarch64"
[[ "$HOST_ARCH" != "aarch64" ]] && \
    die "build-arm64.sh must run on aarch64. Current host: ${HOST_ARCH}"

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

# ── Apply arm64 UML port ─────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="$REPO_ROOT/scripts/patches/uml-arm64"

log "Copying arch/arm64/um port files..."
cp -r "$REPO_ROOT/arch/arm64/Makefile.um" "$SRC_DIR/arch/arm64/"
cp -r "$REPO_ROOT/arch/arm64/um"          "$SRC_DIR/arch/arm64/"
cp -r "$REPO_ROOT/arch/um/configs"        "$SRC_DIR/arch/um/"

log "Applying patches to existing kernel files..."
for p in "$PATCH_DIR"/0*.patch; do
    log "  → $(basename "$p")"
    patch -d "$SRC_DIR" -p1 --forward < "$p"
done
log "Patches applied ($(ls "$PATCH_DIR"/0*.patch | wc -l) patches)."

# ── Configure ────────────────────────────────────────────────────────────────
BUILD_DIR="/tmp/kernel-arm64"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

J="-j$(nproc)"

log "Configuring with arm64_defconfig..."
make -C "$SRC_DIR" O="$BUILD_DIR" ARCH=um arm64_defconfig $J

# ── Compile ──────────────────────────────────────────────────────────────────
log "Compiling UML kernel (~5 min)..."
make -C "$SRC_DIR" O="$BUILD_DIR" ARCH=um $J

# ── Copy output ──────────────────────────────────────────────────────────────
UML_BIN=$(find "$BUILD_DIR" -maxdepth 1 \( -name "linux" -o -name "vmlinux" \) 2>/dev/null | head -1)
[[ -z "$UML_BIN" ]] && die "UML binary not found after build"

DEST="$OUTPUT_DIR/kernel-arm64"
cp "$UML_BIN" "$DEST"
chmod +x "$DEST"
log "Done: kernel-arm64 ($(du -sh "$DEST" | cut -f1))"

# ── Package kernel modules ────────────────────────────────────────────────────
# Install modules into a staging dir, then tar them up.
# The rootfs boot script will extract this tarball into / on first boot.
MODULES_STAGING="$BUILD_DIR/modules-staging"
rm -rf "$MODULES_STAGING"

log "Installing kernel modules..."
make -C "$SRC_DIR" O="$BUILD_DIR" ARCH=um \
    INSTALL_MOD_PATH="$MODULES_STAGING" \
    INSTALL_MOD_STRIP=1 \
    modules_install

# Remove build/source symlinks (they point to CI paths, useless in rootfs)
find "$MODULES_STAGING" -name "build" -o -name "source" | xargs rm -f 2>/dev/null || true

MODULES_TAR="$OUTPUT_DIR/modules-arm64.tar.gz"
tar -czf "$MODULES_TAR" -C "$MODULES_STAGING" lib/
log "Done: modules-arm64.tar.gz ($(du -sh "$MODULES_TAR" | cut -f1))"
log "      $(find "$MODULES_STAGING" -name "*.ko" | wc -l) modules packaged"
