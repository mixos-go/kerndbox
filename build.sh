#!/usr/bin/env bash
# build.sh — Local UML aarch64 kernel build (mirrors CI: ubuntu-24.04-arm)
#
# Usage:
#   ./build.sh              # build kernel
#   ./build.sh --shell      # drop into arm64 container for debugging
#
# Outut:
#   output/linux-uml-aarch64   — UML kernel binary
#   logs/build-<timestamp>.log — full timestamped log

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
LOG_DIR="$REPO_ROOT/logs"
LOG_FILE="$LOG_DIR/build-${TIMESTAMP}.log"
IMAGE="arm64v8/ubuntu:24.04"
ARCH_PLATFORM="linux/arm64"

mkdir -p "$LOG_DIR" "$REPO_ROOT/output"

ts()  { date '+%Y-%m-%dT%H:%M:%S'; }
log() { echo "$(ts)  $*" | tee -a "$LOG_FILE"; }

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  DevBox — UML aarch64 kernel build"
log "  Timestamp : ${TIMESTAMP}"
log "  Log       : ${LOG_FILE}"
log "  Image     : ${IMAGE} (${ARCH_PLATFORM})"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! command -v docker &>/dev/null; then
    log "ERROR: docker not found."
    exit 1
fi

if [[ "$(uname -m)" != "aarch64" ]]; then
    log "Host is x86_64 — registering QEMU arm64 binfmt..."
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes \
        >> "$LOG_FILE" 2>&1
fi

read -r -d '' INNER_SCRIPT <<'INNER' || true
#!/usr/bin/env bash
set -euo pipefail

ts()  { date '+%Y-%m-%dT%H:%M:%S'; }
log() { echo "$(ts)  $*"; }
die() { echo "$(ts)  ERROR: $*" >&2; exit 1; }

KVER="${UML_KERNEL_VERSION:-6.12.74}"
MAJOR="${KVER%%.*}"
TARBALL="/tmp/linux-${KVER}.tar.xz"
SRC="/tmp/linux-${KVER}"
BUILD="/tmp/linux-uml-aarch64"

# ── Install deps ───────────────────────────────────────────────────────────────
log "Installing build dependencies..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential flex bison libssl-dev libelf-dev bc curl ca-certificates \
    > /dev/null

# ── Download + extract ─────────────────────────────────────────────────────────
log "Downloading Linux ${KVER}..."
curl -L --fail --progress-bar \
    "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${KVER}.tar.xz" \
    -o "$TARBALL"

log "Extracting..."
tar -xf "$TARBALL" -C /tmp

# ── Copy our arch/arm64/um files directly (no patch needed) ───────────────────
log "Copying arch/arm64/um port files..."
cp -r /port/arch/arm64/Makefile.um  "$SRC/arch/arm64/"
cp -r /port/arch/arm64/um           "$SRC/arch/arm64/"
cp -r /port/arch/um/configs         "$SRC/arch/um/"

# ── Apply patches to existing kernel files ────────────────────────────────────
log "Applying patches to existing kernel files..."
FAILED=0
for p in /port/scripts/patches/uml-arm64/0*.patch; do
    pname="$(basename "$p")"
    log "  → ${pname}"
    if ! patch -d "$SRC" -p1 --forward < "$p"; then
        log "  FAILED: ${pname}"
        FAILED=1
        break
    fi
done

if [[ $FAILED -eq 1 ]]; then
    log "Patch failed — cleaning up source tree..."
    rm -rf "$SRC" "$TARBALL"
    die "Patch application failed."
fi
log "Done — $(ls /port/scripts/patches/uml-arm64/0*.patch | wc -l) patches applied."

# ── Configure ─────────────────────────────────────────────────────────────────
log "Configuring (ARCH=um)..."
rm -rf "$BUILD"; mkdir -p "$BUILD"
make -C "$SRC" O="$BUILD" ARCH=um defconfig -j"$(nproc)"

cat >> "$BUILD/.config" <<'KCONFIG'
CONFIG_HOSTFS=y
CONFIG_UML_NET_SLIRP=y
CONFIG_BLK_DEV_UBD=y
KCONFIG

make -C "$SRC" O="$BUILD" ARCH=um olddefconfig

# ── Compile ────────────────────────────────────────────────────────────────────
log "Compiling UML kernel ($(nproc) jobs)..."
make -C "$SRC" O="$BUILD" ARCH=um -j"$(nproc)"

# ── Output ────────────────────────────────────────────────────────────────────
BIN="$(find "$BUILD" -maxdepth 1 \( -name "linux" -o -name "vmlinux" \) 2>/dev/null | head -1)"
[[ -z "$BIN" ]] && die "UML binary not found after build"

cp "$BIN" /output/linux-uml-aarch64
chmod +x /output/linux-uml-aarch64
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  SUCCESS: linux-uml-aarch64 ($(du -sh /output/linux-uml-aarch64 | cut -f1))"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
INNER

DOCKER_ARGS=(
    --rm
    --platform "$ARCH_PLATFORM"
    -v "$REPO_ROOT:/port:ro"
    -v "$REPO_ROOT/output:/output"
    -e "UML_KERNEL_VERSION=${UML_KERNEL_VERSION:-6.12.74}"
)

if [[ "${1:-}" == "--shell" ]]; then
    log "Dropping into interactive arm64 shell..."
    docker run -it "${DOCKER_ARGS[@]}" "$IMAGE" bash
    exit 0
fi

log "Launching arm64 container..."
docker run "${DOCKER_ARGS[@]}" "$IMAGE" bash -c "$INNER_SCRIPT" 2>&1 \
    | while IFS= read -r line; do
        echo "$(ts)  ${line}" | tee -a "$LOG_FILE"
      done

STATUS="${PIPESTATUS[0]}"
[[ $STATUS -ne 0 ]] && { log "BUILD FAILED (exit ${STATUS})"; exit "$STATUS"; }
log "Done — output/linux-uml-aarch64 | log: ${LOG_FILE}"
