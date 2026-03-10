#!/usr/bin/env bash
# =============================================================================
# menu.sh — kerndbox interactive menu
# make menu → runs this script
# =============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO/scripts"
OUTPUT="$REPO/output"
HOST_ARCH="$(uname -m)"
[[ "$HOST_ARCH" == "arm64" ]] && HOST_ARCH="aarch64"
KERNEL_VER="${KERNEL_VER:-6.12.74}"
MIRROR="${MIRROR:-https://cdn.kernel.org/pub/linux/kernel}"
GITHUB_REPO="${GITHUB_REPO:-mixos-go/kerndbox}"
GH_TOKEN="${GH_TOKEN:-}"
BOOTSTRAP_TAG="${BOOTSTRAP_TAG:-}"

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    GR='\033[0;32m' YE='\033[1;33m' RE='\033[0;31m'
    CY='\033[0;36m' DI='\033[2m'    BO='\033[1m'    RS='\033[0m'
else
    GR='' YE='' RE='' CY='' DI='' BO='' RS=''
fi

# ── UI primitives ─────────────────────────────────────────────────────────────
cls()   { printf '\033[2J\033[H'; }
hr()    { printf "${DI}%60s${RS}\n" | tr ' ' '─'; }
ok()    { echo -e "  ${GR}✓${RS}  $*"; }
warn()  { echo -e "  ${YE}⚠${RS}  $*"; }
err()   { echo -e "  ${RE}✗${RS}  $*"; }
info()  { echo -e "  ${DI}·  $*${RS}"; }
step()  { echo -e "\n  ${BO}${CY}▶${RS}  $*"; }
pause() { echo; printf "  ${DI}tekan Enter ...${RS} "; read -r _; }

header() {
    echo
    echo -e "  ${BO}${CY}kerndbox${RS}  ${DI}$*${RS}"
    hr
    echo
}

# numbered menu — sets global PICK
menu() {
    local -a labels=() hints=()
    while [[ $# -ge 2 ]]; do labels+=("$1"); hints+=("$2"); shift 2; done

    local i
    for ((i=0; i<${#labels[@]}; i++)); do
        printf "  ${BO}[%d]${RS}  %-14s${DI}%s${RS}\n" \
               $((i+1)) "${labels[$i]}" "${hints[$i]}"
    done
    echo
    printf "  ${BO}›${RS} "
    read -r PICK

    # normalize: number or text
    if [[ "$PICK" =~ ^[0-9]+$ ]]; then
        local idx=$(( PICK - 1 ))
        if [[ $idx -lt 0 || $idx -ge ${#labels[@]} ]]; then
            err "Pilihan tidak valid"; PICK=""; return 1
        fi
        PICK="${labels[$idx]}"
    else
        local found=0 lbl
        for lbl in "${labels[@]}"; do
            if [[ "${PICK,,}" == "${lbl,,}" ]]; then PICK="$lbl"; found=1; break; fi
        done
        [[ $found -eq 1 ]] || { err "Pilihan tidak valid"; PICK=""; return 1; }
    fi
}

ask() {
    # ask OUTVAR "label" [default]
    local _v="$1" _lbl="$2" _def="${3:-}" _in
    if [[ -n "$_def" ]]; then
        printf "  ${BO}$_lbl${RS} ${DI}[$_def]${RS}: "
    else
        printf "  ${BO}$_lbl${RS}: "
    fi
    read -r _in
    printf -v "$_v" '%s' "${_in:-$_def}"
}

# ── Docker helpers ────────────────────────────────────────────────────────────
dc_run() {
    # dc_run <arch> <service-suffix> [cmd...]
    local arch="$1" svc="$2"; shift 2
    docker compose --profile "$arch" run --rm "${svc}-${arch}" "$@"
}

for_arch() {
    # for_arch <arch:arm64|x86|both> <service-suffix> [cmd...]
    local arch="$1" svc="$2"; shift 2
    case "$arch" in
        both)
            step "arm64 ..."; dc_run arm64 "$svc" "$@" || true
            step "x86 ...";   dc_run x86   "$svc" "$@" || true ;;
        *)
            dc_run "$arch" "$svc" "$@" ;;
    esac
}

pick_arch() {
    # sets PICK = arm64 | x86 | both
    local native_arm="" native_x86=""
    [[ "$HOST_ARCH" == "aarch64" ]] && native_arm=" ← host" || native_x86=" ← host"
    menu \
        "arm64"  "UML arm64${native_arm}" \
        "x86"    "UML x86_64${native_x86}" \
        "both"   "arm64 + x86_64 berurutan"
}

# ── Status block ──────────────────────────────────────────────────────────────
status() {
    local k64="$OUTPUT/kernel-arm64"    k86="$OUTPUT/kernel-x86_64"
    local r64="$OUTPUT/debian-rootfs-aarch64.img"
    local r86="$OUTPUT/debian-rootfs-x86_64.img"
    local bk64="—" bk86="—" br64="—" br86="—"

    [[ -f "$k64" ]] && bk64="${GR}$(du -sh "$k64" | cut -f1) ✓${RS}" || bk64="${DI}—${RS}"
    [[ -f "$k86" ]] && bk86="${GR}$(du -sh "$k86" | cut -f1) ✓${RS}" || bk86="${DI}—${RS}"
    [[ -f "$r64" ]] && br64="${GR}$(du -sh "$r64" | cut -f1) ✓${RS}" || br64="${DI}—${RS}"
    [[ -f "$r86" ]] && br86="${GR}$(du -sh "$r86" | cut -f1) ✓${RS}" || br86="${DI}—${RS}"

    printf "  ${DI}%-12s  %-18s  %-18s${RS}\n" "" "arm64" "x86_64"
    echo -e "  kernel      $bk64  /  $bk86"
    echo -e "  rootfs      $br64  /  $br86"
    echo -e "  ${DI}host: $HOST_ARCH   kernel-ver: $KERNEL_VER   repo: $GITHUB_REPO${RS}"
    hr
}

# ── Submenu: kernel ───────────────────────────────────────────────────────────
sub_kernel() {
    while true; do
        cls; header "kernel"
        status
        menu \
            "build"   "Compile UML kernel + modules" \
            "clean"   "Hapus output kernel" \
            "back"    "Kembali" || { pause; continue; }

        case "$PICK" in
            build)
                echo; pick_arch || { pause; continue; }
                local arch="$PICK"
                step "Building kernel-$arch ..."
                for_arch "$arch" "build" build
                pause ;;
            clean)
                echo; pick_arch || { pause; continue; }
                case "$PICK" in
                    arm64) rm -fv "$OUTPUT/kernel-arm64" "$OUTPUT/modules-arm64.tar.gz" 2>/dev/null ;;
                    x86)   rm -fv "$OUTPUT/kernel-x86_64" "$OUTPUT/modules-x86_64.tar.gz" 2>/dev/null ;;
                    both)  rm -fv "$OUTPUT"/kernel-* "$OUTPUT"/modules-* 2>/dev/null ;;
                esac
                ok "Cleaned"
                pause ;;
            back) return ;;
        esac
    done
}

# ── Submenu: rootfs ───────────────────────────────────────────────────────────
sub_rootfs() {
    while true; do
        cls; header "rootfs"
        status
        menu \
            "build"     "Build Debian rootfs lokal (bakes modules)" \
            "download"  "Download dari GitHub Releases" \
            "kernel+rootfs" "Build kernel dulu → build rootfs" \
            "back"      "Kembali" || { pause; continue; }

        case "$PICK" in
            build)
                echo; pick_arch || { pause; continue; }
                step "Building rootfs-$PICK ..."
                for_arch "$PICK" "rootfs" rootfs
                pause ;;
            download)
                echo; pick_arch || { pause; continue; }
                local arch="$PICK"
                ask TAG "Bootstrap tag" "${BOOTSTRAP_TAG:-latest}"
                export BOOTSTRAP_TAG="$TAG"
                step "Downloading rootfs tag=${TAG:-latest} ..."
                for_arch "$arch" "dev" fetch
                pause ;;
            "kernel+rootfs")
                echo; pick_arch || { pause; continue; }
                local arch="$PICK"
                step "1/2 Building kernel ..."
                for_arch "$arch" "build" build
                step "2/2 Building rootfs ..."
                for_arch "$arch" "rootfs" rootfs
                pause ;;
            back) return ;;
        esac
    done
}

# ── Submenu: test ─────────────────────────────────────────────────────────────
sub_test() {
    while true; do
        cls; header "test boot"
        status

        # Readiness check
        local a64_ok=0 x86_ok=0
        [[ -f "$OUTPUT/kernel-arm64"              ]] && \
        [[ -f "$OUTPUT/debian-rootfs-aarch64.img" ]] && a64_ok=1
        [[ -f "$OUTPUT/kernel-x86_64"             ]] && \
        [[ -f "$OUTPUT/debian-rootfs-x86_64.img"  ]] && x86_ok=1

        [[ $a64_ok -eq 1 ]] && ok "arm64  — siap" || warn "arm64  — kernel/rootfs belum ada"
        [[ $x86_ok -eq 1 ]] && ok "x86_64 — siap" || warn "x86_64 — kernel/rootfs belum ada"

        # ptrace check
        local scope; scope=$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo 0)
        [[ "$scope" == "0" ]] && ok "ptrace_scope=0" || warn "ptrace_scope=$scope (perlu 0)"
        echo

        menu \
            "run"   "Boot test pakai output yang ada" \
            "auto"  "Download rootfs yang hilang → test" \
            "full"  "Build kernel → build rootfs → boot test" \
            "back"  "Kembali" || { pause; continue; }

        case "$PICK" in
            run)
                echo; pick_arch || { pause; continue; }
                local arch="$PICK"
                # Gate on readiness
                if [[ "$arch" == "arm64" && $a64_ok -eq 0 ]]; then
                    warn "arm64 belum siap — pakai 'auto' atau build dulu"
                    pause; continue
                fi
                if [[ "$arch" == "x86" && $x86_ok -eq 0 ]]; then
                    warn "x86_64 belum siap — pakai 'auto' atau build dulu"
                    pause; continue
                fi
                # Fix ptrace jika perlu
                if [[ "$scope" != "0" ]]; then
                    printf "  Set ptrace_scope=0? [Y/n]: "
                    read -r ans
                    [[ "${ans,,}" != "n" ]] && sudo sysctl -w kernel.yama.ptrace_scope=0
                fi
                step "Booting $arch ..."
                for_arch "$arch" "test" test
                pause ;;
            auto)
                echo; pick_arch || { pause; continue; }
                local arch="$PICK"
                # Download yang hilang
                local need_dl=0
                [[ "$arch" == "arm64" && $a64_ok -eq 0 ]] && need_dl=1
                [[ "$arch" == "x86"   && $x86_ok -eq 0 ]] && need_dl=1
                [[ "$arch" == "both"  ]] && need_dl=1
                if [[ $need_dl -eq 1 ]]; then
                    step "Downloading rootfs ..."
                    for_arch "$arch" "dev" fetch
                fi
                [[ "$scope" != "0" ]] && sudo sysctl -w kernel.yama.ptrace_scope=0
                step "Boot test $arch ..."
                for_arch "$arch" "test" test
                pause ;;
            full)
                echo; pick_arch || { pause; continue; }
                local arch="$PICK"
                step "1/3 Build kernel ..."
                for_arch "$arch" "build" build
                step "2/3 Build rootfs ..."
                for_arch "$arch" "rootfs" rootfs
                step "3/3 Boot test ..."
                [[ "$scope" != "0" ]] && sudo sysctl -w kernel.yama.ptrace_scope=0
                for_arch "$arch" "test" test
                pause ;;
            back) return ;;
        esac
    done
}

# ── Submenu: patch ────────────────────────────────────────────────────────────
sub_patch() {
    while true; do
        cls; header "patch test"

        local pc sc
        pc=$(ls "$SCRIPTS/patches/uml-arm64"/0*.patch 2>/dev/null | wc -l | tr -d ' ')
        sc=$(find "$REPO/arch/arm64" -type f 2>/dev/null | wc -l | tr -d ' ')
        info "$pc patches  ·  $sc scratch files  ·  Linux $KERNEL_VER"
        echo

        menu \
            "dry"    "Dry-run offline, ref lokal  (~5s)" \
            "local"  "Dry-run + real apply ke /tmp  (~15s)" \
            "up"     "Download Linux $KERNEL_VER → dry-run  (internet)" \
            "full"   "Download + apply + makecheck  (internet)" \
            "list"   "Daftar semua patch + subject" \
            "back"   "Kembali" || { pause; continue; }

        case "$PICK" in
            dry)
                echo; bash "$SCRIPTS/test-patches-local.sh"
                pause ;;
            local)
                echo; bash "$SCRIPTS/test-patches-local.sh" --apply
                pause ;;
            up)
                echo; ask KV "Kernel version" "$KERNEL_VER"
                bash "$SCRIPTS/test-patches-upstream.sh" \
                     --kernel "$KV" --mirror "$MIRROR"
                pause ;;
            full)
                echo; ask KV "Kernel version" "$KERNEL_VER"
                bash "$SCRIPTS/test-patches-upstream.sh" \
                     --kernel "$KV" --mirror "$MIRROR" --apply --makecheck
                pause ;;
            list)
                echo; hr
                printf "  ${DI}%-40s  %s${RS}\n" "PATCH" "SUBJECT"
                hr
                for p in "$SCRIPTS/patches/uml-arm64"/0*.patch; do
                    local subj; subj=$(grep -m1 '^Subject:' "$p" 2>/dev/null | sed 's/Subject: //')
                    printf "  %-40s  ${DI}%s${RS}\n" "$(basename "$p")" "$subj"
                done
                hr
                pause ;;
            back) return ;;
        esac
    done
}

# ── Submenu: shell ────────────────────────────────────────────────────────────
sub_shell() {
    while true; do
        cls; header "shell"
        status

        # Show what's inside dev container
        echo -e "  ${DI}Dev container mounts:${RS}"
        info "/workspace  ← repo root (read-write)"
        info "/output     ← output/ (via -v, jika pakai mode inspect)"
        info "/cache      ← Docker volume: kernel tarball cache"
        echo -e "  ${DI}Available commands di dalam: build  fetch  rootfs  test  all  bash${RS}"
        echo

        menu \
            "dev"     "Shell bash di dev container" \
            "inspect" "Shell + /output mounted read-only (lihat artifact)" \
            "run"     "Jalankan satu command di container" \
            "logs"    "Lihat log output/ terbaru" \
            "back"    "Kembali" || { pause; continue; }

        case "$PICK" in
            dev)
                echo; pick_arch || { pause; continue; }
                local arch="$PICK"
                [[ "$arch" == "both" ]] && arch="arm64"
                echo
                info "Container: dev-$arch  |  cwd: /workspace"
                info "Ketik 'exit' atau Ctrl-D untuk kembali ke menu"
                info "Hint: build / fetch / rootfs / test / all"
                echo
                dc_run "$arch" "dev" bash ;;

            inspect)
                echo; pick_arch || { pause; continue; }
                local arch="$PICK"
                [[ "$arch" == "both" ]] && arch="arm64"
                echo
                info "Container: dev-$arch  |  output/ → /output (ro)"
                info "Ketik 'exit' untuk kembali"
                echo
                mkdir -p "$OUTPUT"
                docker compose --profile "$arch" run --rm \
                    -v "$OUTPUT:/output:ro" \
                    "dev-$arch" bash -c '
                        echo
                        echo "  ── /output ──────────────────────────"
                        ls -lh /output/ 2>/dev/null || echo "  (kosong)"
                        echo
                        exec bash
                    ' ;;

            run)
                echo; pick_arch || { pause; continue; }
                local arch="$PICK"
                [[ "$arch" == "both" ]] && arch="arm64"
                ask CMD "Command" "bash --version"
                echo
                info "Menjalankan: $CMD di dev-$arch"
                dc_run "$arch" "dev" bash -c "$CMD"
                pause ;;

            logs)
                echo
                local latest; latest=$(ls -t "$OUTPUT"/*.log 2>/dev/null | head -1)
                if [[ -n "$latest" ]]; then
                    info "Log terbaru: $latest"
                    echo
                    tail -60 "$latest"
                else
                    warn "Tidak ada file .log di output/"
                fi
                pause ;;

            back) return ;;
        esac
    done
}

# ── Main loop ─────────────────────────────────────────────────────────────────
main() {
    while true; do
        cls
        header "· $(date '+%H:%M') ·"
        status

        menu \
            "kernel"  "Build UML kernel" \
            "rootfs"  "Build / download Debian rootfs" \
            "test"    "Boot test (UML + ptrace)" \
            "patch"   "Test patches & scratch files" \
            "shell"   "Shell di dev container" \
            "quit"    "Keluar"

        case "$PICK" in
            kernel) sub_kernel ;;
            rootfs) sub_rootfs ;;
            test)   sub_test   ;;
            patch)  sub_patch  ;;
            shell)  sub_shell  ;;
            quit)   echo; ok "Bye."; echo; exit 0 ;;
            "")     continue ;;
        esac
    done
}

main
