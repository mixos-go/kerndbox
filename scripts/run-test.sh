#!/usr/bin/env bash
# run-test.sh — Boot test UML kernel with Debian rootfs
#
# Usage:
#   ./scripts/run-test.sh [aarch64|x86_64]
#
# Output:
#   output/boot-{arch}.log  — full log: test messages + UML boot output

set -euo pipefail

HOST_ARCH="$(uname -m)"
[[ "$HOST_ARCH" == "arm64" ]] && HOST_ARCH="aarch64"
ARCH="${1:-$HOST_ARCH}"

case "$ARCH" in
    aarch64|x86_64) ;;
    *) echo "[run-test][ERROR] Unknown arch: $ARCH" >&2; exit 1 ;;
esac

[[ "$ARCH" == "aarch64" ]] && ARCH_OUT="arm64" || ARCH_OUT="$ARCH"

OUTPUT_DIR="$(pwd)/output"
UML_BIN="$OUTPUT_DIR/kernel-${ARCH_OUT}"
ROOTFS="$OUTPUT_DIR/debian-rootfs-${ARCH}.img"
BOOT_LOG="$OUTPUT_DIR/boot-${ARCH_OUT}.log"

mkdir -p "$OUTPUT_DIR"

# ── Tee everything (messages + UML output) to log on host ────────────────────
exec > >(tee "$BOOT_LOG") 2>&1

echo "[run-test] Log: $BOOT_LOG"
echo "[run-test] Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "[run-test] ==========================="

log()  { echo "[run-test] $*"; }
die()  { echo "[run-test][ERROR] $*" >&2; exit 1; }
warn() { echo "[run-test][WARN]  $*"; }

# ── Preflight ────────────────────────────────────────────────────────────────
log "Arch:   $ARCH → output: $ARCH_OUT"
log "Kernel: $UML_BIN"
log "Rootfs: $ROOTFS"

[[ -f "$UML_BIN" ]] || die "Kernel not found: $UML_BIN  (run: make build)"
[[ -f "$ROOTFS"  ]] || die "Rootfs not found: $ROOTFS   (run: make fetch)"

chmod +x "$UML_BIN"
log "Kernel size: $(du -sh "$UML_BIN" | cut -f1)"
log "Rootfs size: $(du -sh "$ROOTFS"  | cut -f1)"

# ── /dev/shm exec check ──────────────────────────────────────────────────────
# UML mmaps executable pages in /dev/shm. Docker mounts it noexec by default.
# Detect and remount exec before UML runs, otherwise:
#   "/dev/shm must be not mounted noexec"
SHM_NOEXEC=0
if grep -qE '\s/dev/shm\s.*\bnoexec\b' /proc/mounts 2>/dev/null; then
    SHM_NOEXEC=1
fi

if [[ $SHM_NOEXEC -eq 1 ]]; then
    warn "/dev/shm is mounted noexec — UML will refuse to start"
    log  "Remounting /dev/shm exec ..."
    if mount -o remount,exec /dev/shm 2>/dev/null; then
        log  "/dev/shm remounted exec ✓"
    else
        # Fallback: create a tmpfs we own in /tmp and point UML at it
        warn "remount failed (no CAP_SYS_ADMIN?) — using TMPDIR fallback"
        UML_TMPDIR="/tmp/uml-shm-$$"
        mkdir -p "$UML_TMPDIR"
        mount -t tmpfs -o exec,size=512M tmpfs "$UML_TMPDIR" 2>/dev/null || {
            warn "tmpfs mount also failed — UML will likely fail with noexec error"
            warn "Fix on host: docker run --tmpfs /dev/shm:exec,size=512m ..."
        }
        export TMPDIR="$UML_TMPDIR"
        log  "TMPDIR=$TMPDIR"
    fi
else
    log "/dev/shm exec ✓"
fi


# ── Boot UML ─────────────────────────────────────────────────────────────────
log "==========================="
log "Booting UML (timeout=90s)..."
log "==========================="

BOOT_PASS=0
set +e

# Use a marker FILE written by the guest, not grep on the log.
# Grep on log is unreliable — bash error messages can contain the magic string.
MARKER_FILE="/tmp/uml-boot-ok-$$"
rm -f "$MARKER_FILE"

# init=/bin/sh reads from stdin (con=fd:0,fd:1).
# We write the marker to a hostfs path so UML can touch it.
# Fallback: also print the marker to stdout so it appears in the log,
# then detect it with grep anchored to line-start to avoid bash error output.
printf 'echo DEVBOX_BOOT_OK; touch %s; poweroff -f\n' "$MARKER_FILE" | \
timeout 90 "$UML_BIN" \
    "ubd0=${ROOTFS}" \
    root=/dev/ubda \
    rootfstype=ext4 \
    mem=512M \
    init=/bin/sh \
    con=fd:0,fd:1

EXIT_CODE=$?
set -e

log "==========================="
log "UML exit code: $EXIT_CODE"

# ── Result ───────────────────────────────────────────────────────────────────
# Check marker file first (reliable), fall back to anchored grep in log.
# grep pattern anchored so bash error messages like
#   "echo 'echo DEVBOX_BOOT_OK ...'" don't match.
if [[ -f "$MARKER_FILE" ]] || grep -qP '^DEVBOX_BOOT_OK$' "$BOOT_LOG" 2>/dev/null; then
    rm -f "$MARKER_FILE"
    log "✅  BOOT TEST PASSED"
    BOOT_PASS=1
else
    rm -f "$MARKER_FILE"
    log "❌  BOOT TEST FAILED"
    grep -q "Kernel panic"          "$BOOT_LOG" && grep "Kernel panic" "$BOOT_LOG" | head -3 | sed 's/^/  /'
    grep -q "VFS: Cannot open root" "$BOOT_LOG" && log "→ Root filesystem mount failed"
    grep -q "No init found"         "$BOOT_LOG" && log "→ init not found in rootfs"
    grep -q "noexec"                "$BOOT_LOG" && log "→ /dev/shm noexec — tambah --tmpfs /dev/shm:exec ke docker run"
    [[ "$EXIT_CODE" -eq 124 ]]                  && log "→ Timeout (90s) — kernel mungkin hang saat boot"
    [[ "$EXIT_CODE" -eq 134 ]]                  && log "→ UML crash (SIGABRT/core dump) — crash sebelum init jalan"
    [[ "$EXIT_CODE" -eq 134 ]]                  && log "  Kemungkinan: modules tidak match rootfs, atau bug di startup code"
    [[ "$EXIT_CODE" -eq 134 ]]                  && log "  Coba: make fetch untuk download rootfs yang match kernel ini"
fi

log "Full log: $BOOT_LOG"
log "Finished: $(date '+%Y-%m-%d %H:%M:%S')"

[[ "$BOOT_PASS" -eq 1 ]]
