#!/usr/bin/env bash
# kerndbox-entrypoint — Helper dispatcher inside the container
#
# Commands:
#   help    Print this help
#   build   Build UML kernel (auto-detects arch)
#   fetch   Download rootfs from GitHub Releases (latest stable by default)
#   test    Run boot test (needs output/ from build + fetch)
#   all     build → fetch → test
#   bash    Drop into interactive shell
#   <any>   Pass-through to bash -c

set -euo pipefail

HOST_ARCH="$(uname -m)"
[[ "$HOST_ARCH" == "arm64" ]] && HOST_ARCH="aarch64"
[[ "$HOST_ARCH" == "aarch64" ]] && ARCH_OUT="arm64" || ARCH_OUT="x86_64"

log()  { echo "[kerndbox] $*"; }
warn() { echo "[kerndbox][WARN] $*" >&2; }

do_build() {
    log "Building UML kernel for $HOST_ARCH..."

    # Cache tarball in /cache volume
    local ver
    ver="$(grep 'UML_KERNEL_VERSION:-' scripts/build-arm64.sh 2>/dev/null \
           | head -1 | sed 's/.*:-\(.*\)}/\1/' || echo "6.12.74")"
    local cached="/cache/linux-${ver}.tar.xz"
    local tmp="/tmp/linux-${ver}.tar.xz"

    [[ -f "$cached" && ! -f "$tmp" ]] && ln -sf "$cached" "$tmp" && log "Using cached tarball"

    case "$HOST_ARCH" in
        aarch64) chmod +x scripts/build-arm64.sh && bash scripts/build-arm64.sh ;;
        x86_64)  chmod +x scripts/build-x86.sh  && bash scripts/build-x86.sh  ;;
        *) echo "[kerndbox][ERROR] Unsupported arch: $HOST_ARCH" >&2; exit 1 ;;
    esac

    # Cache tarball for next run
    [[ -f "$tmp" && ! -f "$cached" ]] && cp "$tmp" "$cached" && log "Tarball cached"

    log "Build output:"
    ls -lh output/kernel-* output/modules-*.tar.gz 2>/dev/null || true
}

do_fetch() {
    log "Fetching rootfs for $HOST_ARCH..."
    chmod +x scripts/fetch-rootfs.sh
    bash scripts/fetch-rootfs.sh "$HOST_ARCH"
}

do_test() {
    log "Running boot test for $HOST_ARCH..."
    chmod +x scripts/run-test.sh
    bash scripts/run-test.sh "$HOST_ARCH"
}

CMD="${1:-help}"
shift || true

case "$CMD" in
    help|--help|-h)
        cat <<EOF

kerndbox dev container — commands:

  build    Build UML kernel + modules (auto-detects arm64 / x86_64)
  fetch    Download rootfs from GitHub Releases (latest stable)
  test     Boot test UML kernel with rootfs
  all      build → fetch → test

  bash     Interactive shell
  help     This message

Env vars:
  GITHUB_REPO      owner/repo  (default: mixos-go/kerndbox)
  GH_TOKEN         GitHub token (optional, for auth)
  BOOTSTRAP_TAG    Pin rootfs version e.g. bootstrap-v1.0.0
                   (omit to use latest stable release)

Output files (after build):
  output/kernel-arm64           UML kernel binary
  output/kernel-x86_64          UML kernel binary
  output/modules-arm64.tar.gz   Kernel modules
  output/modules-x86_64.tar.gz  Kernel modules
  output/debian-rootfs-*.img    Rootfs (from fetch)

EOF
        ;;
    build)   do_build ;;
    fetch)   do_fetch ;;
    test)    do_test  ;;
    all)     do_build; do_fetch; do_test ;;
    bash|sh) exec /bin/bash "$@" ;;
    *)       exec /bin/bash -c "$CMD $*" ;;
esac
