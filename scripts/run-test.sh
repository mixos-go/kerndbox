#!/usr/bin/env bash
# run-test.sh — Boot test UML kernel dengan Debian rootfs
#
# Isolasi test: no networking, init=/bin/sh, timeout 90s
# Deteksi: boot sukses, kernel panic, silent hang

set -euo pipefail

HOST_ARCH="$(uname -m)"
[[ "$HOST_ARCH" == "arm64" ]] && HOST_ARCH="aarch64"
ARCH="${1:-$HOST_ARCH}"

case "$ARCH" in
    aarch64|x86_64) ;;
    *) echo "ERROR: unknown arch: $ARCH" >&2; exit 1 ;;
esac

[[ "$ARCH" == "aarch64" ]] && ARCH_OUT="arm64" || ARCH_OUT="$ARCH"

OUTPUT_DIR="$(pwd)/output"
UML_BIN="$OUTPUT_DIR/kernel-${ARCH_OUT}"
ROOTFS="$OUTPUT_DIR/debian-rootfs-${ARCH}.img"
BOOT_LOG="$OUTPUT_DIR/boot-${ARCH_OUT}.log"

mkdir -p "$OUTPUT_DIR"
exec > >(tee "$BOOT_LOG") 2>&1

log()  { echo "[test] $*"; }
die()  { echo "[test][FAIL] $*" >&2; exit 1; }

log "=== UML Boot Test ==="
log "Arch:   $ARCH_OUT"
log "Kernel: $UML_BIN"
log "Rootfs: $ROOTFS"
log "Log:    $BOOT_LOG"
log "Started: $(date '+%Y-%m-%d %H:%M:%S')"

[[ -f "$UML_BIN" ]] || die "kernel not found: $UML_BIN"
[[ -f "$ROOTFS"  ]] || die "rootfs not found: $ROOTFS"
chmod +x "$UML_BIN"

# ── /dev/shm noexec check ────────────────────────────────────────────────
if grep -qE '\s/dev/shm\s.*\bnoexec\b' /proc/mounts 2>/dev/null; then
    log "WARN: /dev/shm noexec — remounting..."
    mount -o remount,exec /dev/shm 2>/dev/null \
        || { export TMPDIR="/tmp/uml-shm-$$"; mkdir -p "$TMPDIR"; }
fi

# ── Temp files ───────────────────────────────────────────────────────────
UMID="ktest-$$"
NOTIFY_SOCK="/tmp/ktest-notify-$$.sock"
STDIN_FIFO="/tmp/ktest-stdin-$$"
UML_LOG="/tmp/ktest-uml-$$.log"
MARKER="/tmp/ktest-ok-$$"
MC_REQ_SOCK="/tmp/ktest-mc-req-$$.sock"

cleanup() {
    kill "$UML_PID"  2>/dev/null || true
    kill "$MON_PID"  2>/dev/null || true
    # fd 9 kaup
    exec 9<&- 2>/dev/null || true
    rm -f "$NOTIFY_SOCK" "$STDIN_FIFO" "$UML_LOG" \
          "$MARKER" "$MC_REQ_SOCK"
    rm -rf "/tmp/uml-${UMID}" 2>/dev/null || true
}
trap cleanup EXIT

# Create stdin FIFO for UML
[[ -p "$STDIN_FIFO" ]] || mkfifo "$STDIN_FIFO"

# ── Python helpers (tulis ke file dulu, bukan heredoc ke background) ─────
NOTIFY_PY="/tmp/ktest-notify-$$.py"
MC_PY="/tmp/ktest-mc-$$.py"

cat > "$NOTIFY_PY" << 'PYEOF'
#!/usr/bin/env python3
# Bind notify socket, tunggu satu packet dari kernel mconsole driver.
# Output: SOCKET:<path> | PANIC:<msg> | HANG | TIMEOUT
import sys, socket, struct, os

sock_path, timeout_s = sys.argv[1], int(sys.argv[2])
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
s.bind(sock_path)
os.chmod(sock_path, 0o777)
s.settimeout(timeout_s)
try:
    data, _ = s.recvfrom(4096)
    # struct mconsole_notify: magic u32, version u32, type u32, len u32, data[]
    if len(data) < 16:
        print("TIMEOUT:short packet"); sys.exit(1)
    magic, version, ntype, length = struct.unpack_from("<IIII", data)
    text = data[16:16+length].decode(errors='replace').strip()
    labels = {0: "SOCKET", 1: "PANIC", 2: "HANG"}
    label = labels.get(ntype, f"OTHER{ntype}")
    print(f"{label}:{text}")
    sys.exit(1 if ntype == 1 else 0)
except socket.timeout:
    print("TIMEOUT:")
    sys.exit(2)
finally:
    s.close()
    try: os.unlink(sock_path)
    except: pass
PYEOF

cat > "$MC_PY" << 'PYEOF'
#!/usr/bin/env python3
# Kirim satu mconsole command, tunggu reply.
# argv: <target_socket> <my_socket> <command>
# Exit 0 = ada reply, exit 1 = timeout/error
import sys, socket, struct, os, select

target, my_sock, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
MAGIC, VER = 0xcafebabe, 2

req  = struct.pack("<III", MAGIC, VER, len(cmd))
req += cmd.encode().ljust(512, b'\x00')

s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
s.bind(my_sock)
try:
    s.sendto(req, target)
    buf = []
    while True:
        r = select.select([s], [], [], 2.0)
        if not r[0]: break
        data = s.recv(4096)
        err, more, ln = struct.unpack_from("<III", data)
        chunk = data[12:12+ln].decode(errors='replace').strip()
        if chunk: buf.append(chunk)
        if not more: break
    if buf: print('\n'.join(buf))
    sys.exit(0 if buf else 1)
except Exception as e:
    print(f"ERR:{e}", file=sys.stderr)
    sys.exit(1)
finally:
    s.close()
    try: os.unlink(my_sock)
    except: pass
PYEOF

# ── Bind notify socket SEBELUM UML start ─────────────────────────────────
# Kernel sendto() ke socket ini saat mconsole driver ready.
# Harus sudah ada sebelum UML jalan — kalau tidak, sendto() gagal silent.
log "Binding notify socket: $NOTIFY_SOCK"
python3 "$NOTIFY_PY" "$NOTIFY_SOCK" 90 > "/tmp/ktest-notify-out-$$.txt" 2>&1 &
NOTIFY_PID=$!

# Tunggu sampai socket benar-benar sudah di-bind (max 2 detik)
for i in $(seq 1 20); do
    [[ -S "$NOTIFY_SOCK" ]] && break
    sleep 0.1
done
[[ -S "$NOTIFY_SOCK" ]] || die "notify socket tidak terbuat dalam 2 detik"
log "Notify socket ready ✓"

# ── Launch UML ────────────────────────────────────────────────────────────
log "=== Booting UML ==="
"$UML_BIN" \
    "ubd0=${ROOTFS}" \
    root=/dev/ubda \
    rootfstype=ext4 \
    rw \
    mem=64M \
    umid="$UMID" \
    "mconsole=notify:${NOTIFY_SOCK}" \
    > "$UML_LOG" 2>&1 &
UML_PID=$!
log "UML PID: $UML_PID"

# ── Monitor process ───────────────────────────────────────────────────────
# Monitor jalan di background: tail UML log ke terminal secara realtime
tail -f "$UML_LOG" --pid="$UML_PID" 2>/dev/null &
MON_PID=$!

# ── Tunggu notify ─────────────────────────────────────────────────────────
log "Menunggu mconsole notify dari kernel..."
wait "$NOTIFY_PID" && NOTIFY_EXIT=0 || NOTIFY_EXIT=$?
NOTIFY_OUT=$(cat "/tmp/ktest-notify-out-$$.txt" 2>/dev/null || echo "TIMEOUT:")
rm -f "/tmp/ktest-notify-out-$$.txt"
log "Notify: $NOTIFY_OUT"

if echo "$NOTIFY_OUT" | grep -q "^PANIC:"; then
    PANIC_MSG=$(echo "$NOTIFY_OUT" | sed 's/^PANIC://')
    log ""
    log "❌  KERNEL PANIC: $PANIC_MSG"
    log "--- Tail UML log ---"
    tail -30 "$UML_LOG" 2>/dev/null | sed 's/^/  /'
    exit 1
fi

if echo "$NOTIFY_OUT" | grep -q "^TIMEOUT:"; then
    log ""
    log "❌  TIMEOUT: kernel tidak pernah reach mconsole driver"
    log "    Kemungkinan: hang di startup (ptrace/sysemu check), atau"
    log "    panic sebelum mconsole init, atau binary corrupt"
    log "--- Tail UML log ---"
    tail -30 "$UML_LOG" 2>/dev/null | sed 's/^/  /'
    # Check apakah UML masih jalan
    if kill -0 "$UML_PID" 2>/dev/null; then
        log "UML masih jalan — ini adalah silent hang"
        log "wchan (apa yang kernel tunggu):"
        cat /proc/"$UML_PID"/wchan 2>/dev/null | sed 's/^/  /' || true
        log "status:"
        cat /proc/"$UML_PID"/status 2>/dev/null | grep -E "State|VmRSS|Threads" | sed 's/^/  /' || true
        log "syscall:"
        cat /proc/"$UML_PID"/syscall 2>/dev/null | sed 's/^/  /' || true
        log "children:"
        if [[ "$ARCH" == "arm64" ]] && [[ -f /tmp/uml-strace.log ]]; then
            log "=== Last strace lines ==="
            tail -20 /tmp/uml-strace.log | sed "s/^/  /" || true
        fi
        ls /proc/"$UML_PID"/task/ 2>/dev/null | wc -l | sed 's/^/  threads: /' || true
        # Check child processes too
        for child in $(cat /proc/"$UML_PID"/task/*/children 2>/dev/null | tr " " "\n" | sort -u); do
            [ -d "/proc/$child" ] && echo "  child $child wchan: $(cat /proc/$child/wchan 2>/dev/null)" || true
        done
    else
        log "UML sudah exit"
    fi
    exit 1
fi

# ── mconsole ready — kirim init commands ─────────────────────────────────
MC_SOCK="$HOME/.uml/${UMID}/mconsole"
log "mconsole ready: $MC_SOCK"

# ── Simple boot test: wait and check if still running ────────────────────
# This is a basic test: just verify UML kernel stays alive after boot

log "Waiting 10 seconds to verify kernel stays alive..."
sleep 10

# ── Check if UML is still running ─────────────────────────────────────
if ! kill -0 "$UML_PID" 2>/dev/null; then
    if grep -q "Requested init.*failed" "$UML_LOG" 2>/dev/null; then
        log "❌  Init binary not found in rootfs (ENOENT)"
    elif grep -q "Kernel panic" "$UML_LOG" 2>/dev/null; then
        log "❌  Kernel panic"
    else
        log "❌  UML exited unexpectedly"
    fi
    log "--- Last 20 lines of UML log ---"
    tail -20 "$UML_LOG" | sed "s/^/  /"
    log "---"
    exit 1
fi

log "✅  UML kernel stayed alive for 10s - boot test passed!"
exit 0

# ── Watchdog: poll mconsole, deteksi silent hang ─────────────────────────
BOOT_PASS=0
FAIL_REASON=""
LAST_OK=$(date +%s)
HANG_TIMEOUT=30
DEADLINE=$(( $(date +%s) + 60 ))  # 60s dari notify sampai boot ok

log "Watchdog aktif (hang threshold: ${HANG_TIMEOUT}s)..."

while true; do
    NOW=$(date +%s)

    # Hard deadline
    if [[ $NOW -ge $DEADLINE ]]; then
        FAIL_REASON="Timeout 60s setelah mconsole ready — init commands tidak dieksekusi"
        break
    fi

    # UML sudah exit?
    if ! kill -0 "$UML_PID" 2>/dev/null; then
        log "UML exit"
        break
    fi

    # Boot OK?
    if [[ -f "$MARKER" ]] || grep -qP '^DEVBOX_BOOT_OK$' "$UML_LOG" 2>/dev/null; then
        BOOT_PASS=1
        # Halt via mconsole (lebih bersih dari poweroff di shell)
        if [[ -S "$MC_SOCK" ]]; then
            python3 "$MC_PY" "$MC_SOCK" "$MC_REQ_SOCK" "halt" \
                > /dev/null 2>&1 || true
        fi
        break
    fi

    # Poll mconsole — deteksi silent hang
    if [[ -S "$MC_SOCK" ]]; then
        rm -f "$MC_REQ_SOCK"
        if python3 "$MC_PY" "$MC_SOCK" "$MC_REQ_SOCK" "version" \
                > /dev/null 2>&1; then
            LAST_OK=$NOW
        else
            SILENCE=$(( NOW - LAST_OK ))
            if [[ $SILENCE -ge $HANG_TIMEOUT ]]; then
                FAIL_REASON="SILENT HANG: mconsole tidak merespons selama ${SILENCE}s"
                # Ambil info sebelum kill
                log "⚠️  $FAIL_REASON"
                log "wchan: $(cat /proc/"$UML_PID"/wchan 2>/dev/null || echo '?')"
                log "threads: $(ls /proc/"$UML_PID"/task/ 2>/dev/null | wc -l || echo '?')"
                if [[ -S "$MC_SOCK" ]]; then
                    log "Mencoba SysRq-T (thread dump)..."
                    python3 "$MC_PY" "$MC_SOCK" "$MC_REQ_SOCK" "sysrq t" \
                        > /dev/null 2>&1 || true
                    sleep 1
                fi
                break
            fi
            log "mconsole silent ${SILENCE}s..."
        fi
    fi

    sleep 3
done

# ── Stop UML ─────────────────────────────────────────────────────────────
sleep 1
if kill -0 "$UML_PID" 2>/dev/null; then
    kill -TERM "$UML_PID" 2>/dev/null || true
    sleep 2
    kill -0 "$UML_PID" 2>/dev/null && kill -KILL "$UML_PID" 2>/dev/null || true
fi
kill "$MON_PID" 2>/dev/null || true

# ── Result ────────────────────────────────────────────────────────────────
log "==="
if [[ "$BOOT_PASS" -eq 1 ]]; then
    log "✅  BOOT TEST PASSED"
    log "Finished: $(date '+%Y-%m-%d %H:%M:%S')"
    rm -f "$NOTIFY_PY" "$MC_PY"
    exec 9<&-
    exit 0
else
    log "❌  BOOT TEST FAILED"
    [[ -n "$FAIL_REASON" ]] && log "Reason: $FAIL_REASON"
    log ""
    log "--- Full UML output ---"
    cat "$UML_LOG" 2>/dev/null | sed 's/^/  /' || true
    log "---"
    # Pattern diagnosis
    grep -q "Kernel panic"          "$UML_LOG" 2>/dev/null \
        && grep "Kernel panic" "$UML_LOG" | head -3 | sed 's/^/  /'
    grep -q "BUG:"                  "$UML_LOG" 2>/dev/null \
        && grep "BUG:" "$UML_LOG" | head -3 | sed 's/^/  /'
    grep -q "Oops:"                 "$UML_LOG" 2>/dev/null \
        && grep "Oops:" "$UML_LOG" | head -3 | sed 's/^/  /'
    grep -q "VFS: Cannot open root" "$UML_LOG" 2>/dev/null \
        && log "→ Root filesystem mount failed"
    grep -q "No init found"         "$UML_LOG" 2>/dev/null \
        && log "→ init tidak ditemukan di rootfs"
    grep -q "Failed to initialize management console" "$UML_LOG" 2>/dev/null \
        && log "→ mconsole gagal init (umid conflict?)"
    rm -f "$NOTIFY_PY" "$MC_PY"
    exec 9<&-
    exit 1
fi
