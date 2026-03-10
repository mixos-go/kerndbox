#!/usr/bin/env bash
# build-x86.sh — Build UML kernel for x86_64 (DevBox)
#
# MUST run on a native x86_64 host (ubuntu-24.04 runner).
# UML cannot be cross-compiled.
#
# Output: ./output/kernel-x86_64
#
# Usage:
#   ./scripts/build-x86.sh
#   UML_KERNEL_VERSION=6.12.74 ./scripts/build-x86.sh

set -euo pipefail

OUTPUT_DIR="$(pwd)/output"
BUILD_LOG="$OUTPUT_DIR/build-x86_64.log"
UML_KERNEL_VERSION="${UML_KERNEL_VERSION:-6.12.74}"

mkdir -p "$OUTPUT_DIR"

# Tee all output (stdout + stderr) to build log on host output/
exec > >(tee -a "$BUILD_LOG") 2>&1
echo "[build] Log: $BUILD_LOG"
echo "[build] Started: $(date '+%Y-%m-%d %H:%M:%S')"

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
BUILD_DIR="/tmp/kernel-x86_64"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

J="-j$(nproc)"

log "Configuring with defconfig..."
make -C "$SRC_DIR" O="$BUILD_DIR" ARCH=um defconfig $J

# Append essential UML features not in upstream x86_64 defconfig
cat >> "$BUILD_DIR/.config" <<'KCONFIG'
CONFIG_EXT4_USE_FOR_EXT2=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_UNIX98_PTYS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
# CONFIG_COMPACTION is not set
CONFIG_BINFMT_MISC=m
CONFIG_HOSTFS=y
CONFIG_MAGIC_SYSRQ=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_NO_HZ=y
CONFIG_HIGH_RES_TIMERS=y
CONFIG_BSD_PROCESS_ACCT=y
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
CONFIG_LOG_BUF_SHIFT=14
CONFIG_CGROUPS=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CPUSETS=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_CGROUP_SCHED=y
CONFIG_BLK_CGROUP=y
# CONFIG_PID_NS is not set
CONFIG_SYSFS_DEPRECATED=y
CONFIG_CC_OPTIMIZE_FOR_SIZE=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
# CONFIG_BLK_DEV_BSG is not set
CONFIG_IOSCHED_BFQ=m
CONFIG_SSL=y
CONFIG_NULL_CHAN=y
CONFIG_PORT_CHAN=y
CONFIG_PTY_CHAN=y
CONFIG_TTY_CHAN=y
CONFIG_XTERM_CHAN=y
CONFIG_CON_CHAN="pts"
CONFIG_SSL_CHAN="pts"
CONFIG_SOUND=m
CONFIG_UML_SOUND=m
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_BLK_DEV_UBD=y
CONFIG_BLK_DEV_LOOP=m
CONFIG_BLK_DEV_NBD=m
CONFIG_DUMMY=m
CONFIG_TUN=m
CONFIG_PPP=m
CONFIG_SLIP=m
CONFIG_LEGACY_PTY_COUNT=32
# CONFIG_HW_RANDOM is not set
CONFIG_UML_RANDOM=y
CONFIG_NET=y
CONFIG_PACKET=y
CONFIG_UNIX=y
CONFIG_INET=y
# CONFIG_IPV6 is not set
CONFIG_UML_NET=y
CONFIG_UML_NET_ETHERTAP=y
CONFIG_UML_NET_TUNTAP=y
CONFIG_UML_NET_SLIP=y
CONFIG_UML_NET_DAEMON=y
CONFIG_UML_NET_MCAST=y
CONFIG_UML_NET_SLIRP=y
CONFIG_EXT4_FS=y
CONFIG_REISERFS_FS=y
CONFIG_QUOTA=y
CONFIG_AUTOFS_FS=m
CONFIG_ISO9660_FS=m
CONFIG_JOLIET=y
CONFIG_PROC_KCORE=y
CONFIG_TMPFS=y
CONFIG_NLS=y
CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y
CONFIG_FRAME_WARN=1024
CONFIG_DEBUG_KERNEL=y
KCONFIG

make -C "$SRC_DIR" O="$BUILD_DIR" ARCH=um olddefconfig

# ── Compile ──────────────────────────────────────────────────────────────────
log "Compiling UML kernel (~5 min)..."
make -C "$SRC_DIR" O="$BUILD_DIR" ARCH=um $J

# ── Copy output ──────────────────────────────────────────────────────────────
UML_BIN=$(find "$BUILD_DIR" -maxdepth 1 \( -name "linux" -o -name "vmlinux" \) 2>/dev/null | head -1)
[[ -z "$UML_BIN" ]] && die "UML binary not found after build"

DEST="$OUTPUT_DIR/kernel-x86_64"
cp "$UML_BIN" "$DEST"
chmod +x "$DEST"
log "Done: kernel-x86_64 ($(du -sh "$DEST" | cut -f1))"

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

MODULES_TAR="$OUTPUT_DIR/modules-x86_64.tar.gz"
tar -czf "$MODULES_TAR" -C "$MODULES_STAGING" lib/
log "Done: modules-x86_64.tar.gz ($(du -sh "$MODULES_TAR" | cut -f1))"
log "      $(find "$MODULES_STAGING" -name "*.ko" | wc -l) modules packaged"
