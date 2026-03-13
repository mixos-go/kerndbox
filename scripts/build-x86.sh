#!/usr/bin/env bash
# build-x86.sh — Build UML kernel for x86_64 (DevBox)
#
# MUST run on a native x86_64 host (debian:bookworm container (ubuntu-24.04 runner)).
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
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$OUTPUT_DIR"

# Tee all output (stdout + stderr) to build log on host output/
exec > >(tee -a "$BUILD_LOG") 2>&1
echo "[build] Log: $BUILD_LOG"
echo "[build] Started: $(date '+%Y-%m-%d %H:%M:%S')"

log() { echo "[DevBox] $*"; }
die() { echo "[DevBox][ERROR] $*" >&2; exit 1; }

# ── Install build dependencies (apt) ─────────────────────────────────────────
log "Installing build dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    `# Core toolchain` \
    gcc g++ binutils make bash pkg-config \
    `# Kernel build essentials` \
    flex bison bc libssl-dev libelf-dev libncurses-dev \
    `# BTF / DWARF / BPF debug info` \
    pahole dwarves libdw-dev \
    `# LLVM + Clang (bindgen uses libclang)` \
    llvm clang libclang-dev lld \
    `# Kernel scripts + utils` \
    python3 perl gawk \
    rsync kmod cpio \
    xz-utils tar gzip bzip2 zstd \
    openssl \
    zlib1g-dev \
    `# Misc` \
    git patch diffutils wget curl ca-certificates \
    util-linux e2fsprogs \
    u-boot-tools



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

# ── Rust + bindgen ────────────────────────────────────────────────────────────
# Debian bookworm rustc (1.63) too old — kernel 6.12 needs 1.78.0+
# Debian bookworm bindgen (0.60.1) too old — kernel needs 0.65.1+

# GitHub Actions runner sets $HOME=/github/home, but euid passwd entry is /root.
# rustup validates $HOME == getpwuid(euid)->pw_dir and aborts if they differ.
# Fix: set HOME to what passwd says for current uid BEFORE any rustup invocation.
export HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"
# Pin RUSTUP_HOME and CARGO_HOME to stable paths (not inside $HOME).
export RUSTUP_HOME="/opt/rustup"
export CARGO_HOME="/opt/cargo"
export PATH="/opt/cargo/bin:$PATH"
log "HOME=$HOME  RUSTUP_HOME=$RUSTUP_HOME  CARGO_HOME=$CARGO_HOME" 

if ! command -v rustup >/dev/null 2>&1; then
    log "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo \
          sh -s -- -y --no-modify-path --default-toolchain none
fi

# Read required Rust version from kernel source
RUST_VER="$("$SRC_DIR/scripts/min-tool-version.sh" rustc 2>/dev/null | head -1 || echo '1.82.0')"
log "Installing Rust ${RUST_VER}..."
rustup toolchain install "${RUST_VER}" --profile minimal
rustup component add rust-src rustfmt clippy
rustup override set "${RUST_VER}"

# bindgen via cargo (apt version too old — needs 0.65.1+)
if ! command -v bindgen >/dev/null 2>&1; then
    log "Installing bindgen..."
    cargo install --locked bindgen-cli
fi
log "Toolchain: gcc=$(gcc --version | head -1) | rustc=$(rustc --version) | bindgen=$(bindgen --version)"

# ── Make variables ─────────────────────────────────────────────────────────────
# Pass explicit paths so kernel Makefile finds our rustup-installed toolchain
# regardless of PATH ordering inside make sub-processes.
MAKE_VARS=(
    ARCH=um
    SUBARCH=x86_64
    # rust/Makefile resolves: BINDGEN_TARGET := BINDGEN_TARGET_$(SRCARCH)
    # With ARCH=um → SRCARCH=um → BINDGEN_TARGET_um undefined → empty string
    # → bindgen gets --target '' → panics "unknown target triple 'unknown'"
    # Fix: pass the host triple explicitly.
    BINDGEN_TARGET=x86_64-linux-gnu
    RUSTC="/opt/cargo/bin/rustc"
    BINDGEN="/opt/cargo/bin/bindgen"
    RUSTFMT="/opt/cargo/bin/rustfmt"
    HOSTRUSTC="/opt/cargo/bin/rustc"
)

# ── Configure ────────────────────────────────────────────────────────────────
# x86_64 UML uses upstream defconfig — no custom port needed.
# We only append essential DevBox features on top.
BUILD_DIR="/tmp/kernel-x86_64"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

J="-j$(nproc)"

# Verify Rust toolchain usable before build
log "Verifying Rust toolchain (make rustavailable)..."
make -C "$SRC_DIR" O="$BUILD_DIR" "${MAKE_VARS[@]}" rustavailable \
    || die "Rust toolchain not available — check rustc/bindgen versions"

log "Configuring with defconfig..."
make -C "$SRC_DIR" O="$BUILD_DIR" "${MAKE_VARS[@]}" defconfig $J

# Set essential UML features using scripts/config (the proper kernel tool).
# This avoids duplicate-symbol warnings and handles quoting correctly.
SC="$SRC_DIR/scripts/config"
$SC --file "$BUILD_DIR/.config" --enable  EXT4_USE_FOR_EXT2
$SC --file "$BUILD_DIR/.config" --enable  BINFMT_ELF
$SC --file "$BUILD_DIR/.config" --enable  BINFMT_SCRIPT
$SC --file "$BUILD_DIR/.config" --enable  UNIX98_PTYS
$SC --file "$BUILD_DIR/.config" --enable  PROC_FS
$SC --file "$BUILD_DIR/.config" --enable  SYSFS
$SC --file "$BUILD_DIR/.config" --disable COMPACTION
$SC --file "$BUILD_DIR/.config" --module  BINFMT_MISC
$SC --file "$BUILD_DIR/.config" --enable  HOSTFS
$SC --file "$BUILD_DIR/.config" --enable  MAGIC_SYSRQ
$SC --file "$BUILD_DIR/.config" --enable  SYSVIPC
$SC --file "$BUILD_DIR/.config" --enable  POSIX_MQUEUE
$SC --file "$BUILD_DIR/.config" --enable  NO_HZ
$SC --file "$BUILD_DIR/.config" --enable  HIGH_RES_TIMERS
$SC --file "$BUILD_DIR/.config" --enable  BSD_PROCESS_ACCT
$SC --file "$BUILD_DIR/.config" --enable  IKCONFIG
$SC --file "$BUILD_DIR/.config" --enable  IKCONFIG_PROC
$SC --file "$BUILD_DIR/.config" --set-val LOG_BUF_SHIFT 14
$SC --file "$BUILD_DIR/.config" --enable  CGROUPS
$SC --file "$BUILD_DIR/.config" --enable  CGROUP_FREEZER
$SC --file "$BUILD_DIR/.config" --enable  CGROUP_DEVICE
$SC --file "$BUILD_DIR/.config" --enable  CPUSETS
$SC --file "$BUILD_DIR/.config" --enable  CGROUP_CPUACCT
$SC --file "$BUILD_DIR/.config" --enable  CGROUP_SCHED
$SC --file "$BUILD_DIR/.config" --enable  BLK_CGROUP
$SC --file "$BUILD_DIR/.config" --disable PID_NS
$SC --file "$BUILD_DIR/.config" --enable  SYSFS_DEPRECATED
$SC --file "$BUILD_DIR/.config" --enable  CC_OPTIMIZE_FOR_SIZE
$SC --file "$BUILD_DIR/.config" --enable  MODULES
$SC --file "$BUILD_DIR/.config" --enable  MODULE_UNLOAD
$SC --file "$BUILD_DIR/.config" --disable BLK_DEV_BSG
$SC --file "$BUILD_DIR/.config" --module  IOSCHED_BFQ
$SC --file "$BUILD_DIR/.config" --enable  SSL
$SC --file "$BUILD_DIR/.config" --enable  NULL_CHAN
$SC --file "$BUILD_DIR/.config" --enable  PORT_CHAN
$SC --file "$BUILD_DIR/.config" --enable  PTY_CHAN
$SC --file "$BUILD_DIR/.config" --enable  TTY_CHAN
$SC --file "$BUILD_DIR/.config" --enable  XTERM_CHAN
$SC --file "$BUILD_DIR/.config" --set-str CON_CHAN "pts"
$SC --file "$BUILD_DIR/.config" --set-str SSL_CHAN "pts"
$SC --file "$BUILD_DIR/.config" --module  SOUND
$SC --file "$BUILD_DIR/.config" --module  UML_SOUND
$SC --file "$BUILD_DIR/.config" --enable  DEVTMPFS
$SC --file "$BUILD_DIR/.config" --enable  DEVTMPFS_MOUNT
$SC --file "$BUILD_DIR/.config" --enable  BLK_DEV_UBD
$SC --file "$BUILD_DIR/.config" --module  BLK_DEV_LOOP
$SC --file "$BUILD_DIR/.config" --module  BLK_DEV_NBD
$SC --file "$BUILD_DIR/.config" --module  DUMMY
$SC --file "$BUILD_DIR/.config" --module  TUN
$SC --file "$BUILD_DIR/.config" --module  PPP
$SC --file "$BUILD_DIR/.config" --module  SLIP
$SC --file "$BUILD_DIR/.config" --set-val LEGACY_PTY_COUNT 32
$SC --file "$BUILD_DIR/.config" --disable HW_RANDOM
$SC --file "$BUILD_DIR/.config" --enable  UML_RANDOM
$SC --file "$BUILD_DIR/.config" --enable  NET
$SC --file "$BUILD_DIR/.config" --enable  PACKET
$SC --file "$BUILD_DIR/.config" --enable  UNIX
$SC --file "$BUILD_DIR/.config" --enable  INET
$SC --file "$BUILD_DIR/.config" --disable IPV6
$SC --file "$BUILD_DIR/.config" --enable  UML_NET
$SC --file "$BUILD_DIR/.config" --enable  UML_NET_ETHERTAP
$SC --file "$BUILD_DIR/.config" --enable  UML_NET_TUNTAP
$SC --file "$BUILD_DIR/.config" --enable  UML_NET_SLIP
$SC --file "$BUILD_DIR/.config" --enable  UML_NET_DAEMON
$SC --file "$BUILD_DIR/.config" --enable  UML_NET_MCAST
$SC --file "$BUILD_DIR/.config" --enable  UML_NET_SLIRP
$SC --file "$BUILD_DIR/.config" --enable  EXT4_FS
$SC --file "$BUILD_DIR/.config" --enable  REISERFS_FS
$SC --file "$BUILD_DIR/.config" --enable  QUOTA
$SC --file "$BUILD_DIR/.config" --module  AUTOFS_FS
$SC --file "$BUILD_DIR/.config" --module  ISO9660_FS
$SC --file "$BUILD_DIR/.config" --enable  JOLIET
$SC --file "$BUILD_DIR/.config" --enable  PROC_KCORE
$SC --file "$BUILD_DIR/.config" --enable  TMPFS
$SC --file "$BUILD_DIR/.config" --enable  NLS
$SC --file "$BUILD_DIR/.config" --enable  DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
$SC --file "$BUILD_DIR/.config" --set-val FRAME_WARN 1024
$SC --file "$BUILD_DIR/.config" --enable  DEBUG_KERNEL
$SC --file "$BUILD_DIR/.config" --enable  RUST
unset SC
make -C "$SRC_DIR" O="$BUILD_DIR" "${MAKE_VARS[@]}" olddefconfig

# ── Compile ──────────────────────────────────────────────────────────────────
log "Compiling UML kernel (~5 min)..."
make -C "$SRC_DIR" O="$BUILD_DIR" "${MAKE_VARS[@]}" $J

# ── Build UML helper utilities (static) ─────────────────────────────────────
# Compile ALL helpers as static binaries for embedding inside kernel ELF.
# Kernel-called (MUST embed): port-helper, uml_watchdog
# Operator tools (convenience): uml_mconsole, uml_mkcow, tunctl
# uml_switch comes from kernel tools/uml/ (built separately below)
log "Building UML helper utilities (static)..."
HELPERS_SRC="$REPO_ROOT/src/uml-helpers"
HELPERS_BUILD="$BUILD_DIR/uml-helpers"
mkdir -p "$HELPERS_BUILD"

for helper in port-helper uml_watchdog uml_mconsole uml_mkcow tunctl; do
    gcc -O2 -static -fno-pie -no-pie \
        -o "$HELPERS_BUILD/$helper" \
        "$HELPERS_SRC/${helper}.c" 2>/dev/null && \
        strip "$HELPERS_BUILD/$helper" && \
        log "  → $helper ($(du -sh "$HELPERS_BUILD/$helper" | cut -f1))" \
        || log "  WARNING: $helper build failed"
done

# uml_switch: built directly from tools/uml/ subdir (bypass top-level kernel
# Makefile to avoid syncconfig flood and wrong 'tools/uml' target name).
log "Building uml_switch (tools/uml)..."
mkdir -p "$BUILD_DIR/tools/uml"
make -C "$SRC_DIR/tools/uml" OUTPUT="$BUILD_DIR/tools/uml/" $J \
    || log "WARNING: tools/uml build failed (uml_switch will be absent)"
SW_SRC=$(find "$BUILD_DIR/tools/uml" "$SRC_DIR/tools/uml" -name "uml_switch" -type f 2>/dev/null | head -1)
if [[ -n "$SW_SRC" ]]; then
    cp "$SW_SRC" "$HELPERS_BUILD/uml_switch"
    strip "$HELPERS_BUILD/uml_switch" 2>/dev/null || true
    log "  → uml_switch ($(du -sh "$HELPERS_BUILD/uml_switch" | cut -f1))"
fi

# Pack all helpers into one .uml_helpers bundle
HELPERS_BIN="$HELPERS_BUILD/uml_helpers.bin"
HELPERS_ARGS=()
for b in port-helper uml_watchdog uml_mconsole uml_mkcow tunctl uml_switch; do
    [[ -f "$HELPERS_BUILD/$b" ]] && HELPERS_ARGS+=("$HELPERS_BUILD/$b")
done

if [[ ${#HELPERS_ARGS[@]} -gt 0 ]]; then
    python3 "$HELPERS_SRC/pack_helpers.py" -o "$HELPERS_BIN" "${HELPERS_ARGS[@]}"
    log "Helpers bundle: $(du -sh "$HELPERS_BIN" | cut -f1) (${#HELPERS_ARGS[@]} binaries)"
else
    log "WARNING: No helpers to embed"
fi

# ── Embed helpers into kernel ELF via objcopy ────────────────────────────────
# Injects .uml_helpers section — linker symbols __uml_helpers_start/end
# are referenced by arch/um/os-Linux/helpers_embed.c at runtime.
UML_BIN_SRC=$(find "$BUILD_DIR" -maxdepth 1 \( -name "linux" -o -name "vmlinux" \) 2>/dev/null | head -1)
[[ -z "$UML_BIN_SRC" ]] && die "UML binary not found after build"

UML_BIN_FINAL="$OUTPUT_DIR/kernel-x86_64"

if [[ -f "$HELPERS_BIN" ]]; then
    log "Injecting .uml_helpers section into kernel ELF..."
    objcopy --add-section .uml_helpers="$HELPERS_BIN" --set-section-flags .uml_helpers=alloc,load,readonly "$UML_BIN_SRC" "$UML_BIN_FINAL"
    chmod +x "$UML_BIN_FINAL"

    # Verify injection
    INJECTED=$(objdump -h "$UML_BIN_FINAL" 2>/dev/null | grep ".uml_helpers" | awk '{print $3}')
    if [[ -n "$INJECTED" ]]; then
        log "✓ .uml_helpers injected: 0x${INJECTED} bytes"
    else
        log "WARNING: .uml_helpers section not found after objcopy"
    fi
else
    # No helpers — just copy the kernel binary as-is
    cp "$UML_BIN_SRC" "$UML_BIN_FINAL"
    chmod +x "$UML_BIN_FINAL"
fi

log "Done: kernel-x86_64 ($(du -sh "$UML_BIN_FINAL" | cut -f1)) — self-contained with embedded helpers"

# ── Package kernel modules ────────────────────────────────────────────────────
# Install modules into a staging dir, then tar them up.
# The rootfs boot script will extract this tarball into / on first boot.
MODULES_STAGING="$BUILD_DIR/modules-staging"
rm -rf "$MODULES_STAGING"

log "Installing kernel modules..."
make -C "$SRC_DIR" O="$BUILD_DIR" "${MAKE_VARS[@]}" \
    INSTALL_MOD_PATH="$MODULES_STAGING" \
    INSTALL_MOD_STRIP=1 \
    modules_install

# Remove build/source symlinks (they point to CI paths, useless in rootfs)
find "$MODULES_STAGING" -name "build" -o -name "source" | xargs rm -f 2>/dev/null || true

MODULES_TAR="$OUTPUT_DIR/modules-x86_64.tar.gz"
tar -czf "$MODULES_TAR" -C "$MODULES_STAGING" lib/
log "Done: modules-x86_64.tar.gz ($(du -sh "$MODULES_TAR" | cut -f1))"
log "      $(find "$MODULES_STAGING" -name "*.ko" | wc -l) modules packaged"
