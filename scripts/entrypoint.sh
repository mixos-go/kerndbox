#!/usr/bin/env bash
# kerndbox-entrypoint — Dispatcher inside the dev container
#
# Commands:
#   build          Build UML kernel + modules
#   rootfs         Build Debian rootfs (bakes modules if present)
#   fetch          Download rootfs from GitHub Releases
#   test           Boot test UML kernel
#   all            build → fetch → test          (download workflow)
#   all-local      build → rootfs → test         (local rootfs workflow)
#   status         Show what's been built in output/
#   bash / sh      Interactive shell
#   help           This help text
#   <anything>     Pass-through: bash -c "<anything>"

set -euo pipefail

CONTAINER_ARCH="$(uname -m)"
[[ "$CONTAINER_ARCH" == "arm64" ]] && CONTAINER_ARCH="aarch64"
[[ "$CONTAINER_ARCH" == "aarch64" ]] && ARCH_OUT="arm64" || ARCH_OUT="x86_64"

log()  { echo "[kerndbox] $*"; }
warn() { echo "[kerndbox][WARN]  $*" >&2; }
err()  { echo "[kerndbox][ERROR] $*" >&2; }

# ── Build kernel ──────────────────────────────────────────────────────────────
do_build() {
    log "Building UML kernel for $CONTAINER_ARCH ..."

    # Reuse cached tarball from Docker volume if available
    local ver
    ver="$(grep -o 'UML_KERNEL_VERSION:-[^}]*' scripts/build-arm64.sh 2>/dev/null \
           | head -1 | sed 's/.*:-//' || echo "6.12.74")"
    local cached="/cache/linux-${ver}.tar.xz"
    local tmp="/tmp/linux-${ver}.tar.xz"
    if [[ -f "$cached" && ! -f "$tmp" ]]; then
        log "Tarball cache hit: $cached"
        cp "$cached" "$tmp"
    fi

    case "$CONTAINER_ARCH" in
        aarch64) chmod +x scripts/build-arm64.sh && bash scripts/build-arm64.sh ;;
        x86_64)  chmod +x scripts/build-x86.sh  && bash scripts/build-x86.sh  ;;
        *) err "Unsupported arch: $CONTAINER_ARCH"; exit 1 ;;
    esac

    # Populate cache volume for next run
    if [[ -f "$tmp" && ! -f "$cached" ]]; then
        cp "$tmp" "$cached"
        log "Tarball cached: $cached"
    fi

    do_status
}

# ── Build rootfs locally ──────────────────────────────────────────────────────
do_rootfs() {
    log "Building Debian rootfs for $CONTAINER_ARCH ..."

    local modules_tar="$(pwd)/output/modules-${ARCH_OUT}.tar.gz"
    local modules_var="MODULES_TAR_$(echo "$ARCH_OUT" | tr '[:lower:]' '[:upper:]' | tr - _)"

    if [[ -f "$modules_tar" ]]; then
        log "Baking modules: $modules_tar"
        export "${modules_var}=${modules_tar}"
    else
        warn "No modules tarball — rootfs will have empty /lib/modules/"
        warn "Run 'build' first, or set ${modules_var}=<path>"
        export "${modules_var}="
    fi

    chmod +x scripts/build-debian-image.sh
    bash scripts/build-debian-image.sh "$CONTAINER_ARCH"

    do_status
}

# ── Fetch rootfs from GitHub Releases ────────────────────────────────────────
do_fetch() {
    log "Fetching rootfs for $CONTAINER_ARCH ..."
    chmod +x scripts/fetch-rootfs.sh
    bash scripts/fetch-rootfs.sh "$CONTAINER_ARCH"
    do_status
}

# ── Boot test ─────────────────────────────────────────────────────────────────
do_test() {
    log "Boot test for $CONTAINER_ARCH ..."
    chmod +x scripts/run-test.sh
    bash scripts/run-test.sh "$CONTAINER_ARCH"
}

# ── Status summary ────────────────────────────────────────────────────────────
do_status() {
    echo
    echo "[kerndbox] ── output/ ──────────────────────────────────────"
    local found=0
    for f in \
        "output/kernel-bundle-arm64.tar.gz"  \
        "output/kernel-bundle-x86_64.tar.gz" \
        "output/kernel-arm64"                \
        "output/kernel-x86_64"               \
        "output/modules-arm64.tar.gz"         \
        "output/modules-x86_64.tar.gz"        \
        "output/debian-rootfs-aarch64.img"    \
        "output/debian-rootfs-x86_64.img"
    do
        if [[ -f "$f" ]]; then
            printf "[kerndbox]   ✓  %-42s  %s\n" "$f" "$(du -sh "$f" | cut -f1)"
            found=1
        fi
    done
    [[ $found -eq 0 ]] && echo "[kerndbox]   (empty)"
    echo "[kerndbox] ────────────────────────────────────────────────"
    echo
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
CMD="${1:-help}"
shift || true

case "$CMD" in
    build)
        do_build ;;

    rootfs)
        do_rootfs ;;

    fetch)
        do_fetch ;;

    test)
        do_test ;;

    # Download workflow: build kernel → download rootfs → test
    all)
        log "all: build → fetch → test"
        do_build
        do_fetch
        do_test ;;

    # Local rootfs workflow: build kernel → build rootfs → test
    all-local)
        log "all-local: build → rootfs → test"
        do_build
        do_rootfs
        do_test ;;

    status)
        do_status ;;

    bash|sh)
        exec /bin/bash "$@" ;;

    help|--help|-h)
        cat << HELP

  kerndbox dev container  ·  arch: $CONTAINER_ARCH

  Commands:
    build        Build UML kernel + modules
    rootfs       Build Debian rootfs locally (bakes modules if present)
    fetch        Download rootfs from GitHub Releases
    test         Boot test UML kernel + rootfs
    status       Show what's in output/

    all          build → fetch → test          (download rootfs from Release)
    all-local    build → rootfs → test         (build rootfs locally)

    bash         Interactive shell
    help         This message

  Env vars:
    GITHUB_REPO      owner/repo  (default: mixos-go/kerndbox)
    GH_TOKEN         GitHub token (for private repo / rate limit)
    BOOTSTRAP_TAG    Pin rootfs release tag  (default: latest)

  Output:
    output/kernel-bundle-{arch}.tar.gz  Kernel ELF + uml_switch + port-helper
    output/kernel-{arch}                Kernel ELF (extracted from bundle)
    output/modules-{arch}.tar.gz        Kernel modules
    output/debian-rootfs-{arch}.img     Rootfs image

HELP
        ;;

    *)
        # Pass-through: anything else runs as bash -c
        exec /bin/bash -c "$CMD $*" ;;
esac
