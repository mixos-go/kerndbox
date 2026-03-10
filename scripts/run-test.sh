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

# ── ptrace_scope check ───────────────────────────────────────────────────────
PTRACE_SCOPE="$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo 0)"
if [[ "$PTRACE_SCOPE" -gt 0 ]]; then
    warn "kernel.yama.ptrace_scope=$PTRACE_SCOPE — UML needs 0 on the HOST"
    warn "Host: sudo sysctl -w kernel.yama.ptrace_scope=0"
    warn "Continuing — may fail..."
else
    log "ptrace_scope=0 ✓"
fi

# ── Boot UML ─────────────────────────────────────────────────────────────────
log "==========================="
log "Booting UML (timeout=90s)..."
log "==========================="

BOOT_PASS=0
set +e

echo 'echo DEVBOX_BOOT_OK && poweroff -f' | \
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
# Re-read log to check for magic string (we tee'd UML output into same file)
if grep -q "DEVBOX_BOOT_OK" "$BOOT_LOG"; then
    log "✅  BOOT TEST PASSED"
    BOOT_PASS=1
else
    log "❌  BOOT TEST FAILED"
    grep -q "Kernel panic"          "$BOOT_LOG" && grep "Kernel panic" "$BOOT_LOG" | head -3 | sed 's/^/  /'
    grep -q "VFS: Cannot open root" "$BOOT_LOG" && log "→ Root filesystem mount failed"
    grep -q "No init found"         "$BOOT_LOG" && log "→ init=/bin/sh not found in rootfs"
    grep -q "check_ptrace\|ptrace"  "$BOOT_LOG" && log "→ ptrace failure — host: sudo sysctl -w kernel.yama.ptrace_scope=0"
    grep -q "noexec"                "$BOOT_LOG" && log "→ /dev/shm noexec — tambah --tmpfs /dev/shm:exec ke docker run, atau privileged=true"
    [[ "$EXIT_CODE" -eq 124 ]]                  && log "→ Timeout (90s)"
fi

log "Full log: $BOOT_LOG"
log "Finished: $(date '+%Y-%m-%d %H:%M:%S')"

[[ "$BOOT_PASS" -eq 1 ]]
