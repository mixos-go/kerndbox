#!/usr/bin/env bash
# fetch-rootfs.sh — Download pre-built Debian rootfs from GitHub Releases
#
# Usage:
#   ./scripts/fetch-rootfs.sh [aarch64|x86_64]
#
# By default downloads the latest stable release (--latest flag).
# Pin to a specific version with BOOTSTRAP_TAG:
#   BOOTSTRAP_TAG=bootstrap-v1.0.0 ./scripts/fetch-rootfs.sh
#
# NOTE: rootfs dari GitHub Releases sudah mengandung kernel modules
#       (baked saat CI build). Tidak perlu inject manual.

set -euo pipefail

log()  { echo "[fetch-rootfs] $*"; }
die()  { echo "[fetch-rootfs][ERROR] $*" >&2; exit 1; }
warn() { echo "[fetch-rootfs][WARN] $*" >&2; }

HOST_ARCH="$(uname -m)"
[[ "$HOST_ARCH" == "arm64" ]] && HOST_ARCH="aarch64"
ARCH="${1:-$HOST_ARCH}"

case "$ARCH" in
    aarch64|x86_64) ;;
    *) die "Unknown arch: $ARCH" ;;
esac

OUTPUT_DIR="$(pwd)/output"
mkdir -p "$OUTPUT_DIR"

GITHUB_REPO="${GITHUB_REPO:-mixos-go/kerndbox}"
DEST="$OUTPUT_DIR/debian-rootfs-${ARCH}.img"

log "Repo: $GITHUB_REPO  Arch: $ARCH"

if [[ -f "$DEST" ]]; then
    log "Already exists: $DEST ($(du -sh "$DEST" | cut -f1)) — skip"
    log "  Delete to re-download: rm -f $DEST"
    exit 0
fi

# ── Download ──────────────────────────────────────────────────────────────────
# BOOTSTRAP_TAG kosong → ambil release --latest (label latest di GitHub)
# BOOTSTRAP_TAG=bootstrap-v1.0.0 → pin ke versi spesifik
BOOTSTRAP_TAG="${BOOTSTRAP_TAG:-}"

if command -v gh >/dev/null 2>&1; then
    if [[ -n "$BOOTSTRAP_TAG" ]]; then
        log "Downloading from tag: $BOOTSTRAP_TAG"
        gh release download "$BOOTSTRAP_TAG" \
            --repo "$GITHUB_REPO" \
            --pattern "debian-rootfs-${ARCH}.img" \
            --dir "$OUTPUT_DIR" \
            --clobber
    else
        log "Downloading from latest stable release..."
        gh release download \
            --repo "$GITHUB_REPO" \
            --pattern "debian-rootfs-${ARCH}.img" \
            --dir "$OUTPUT_DIR" \
            --clobber
    fi
else
    # Fallback curl via GitHub API
    warn "gh not found — falling back to curl"
    [[ -n "${GH_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer ${GH_TOKEN}") || AUTH=()

    if [[ -n "$BOOTSTRAP_TAG" ]]; then
        API="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${BOOTSTRAP_TAG}"
    else
        API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    fi

    URL="$(curl -fsSL "${AUTH[@]}" "$API" | python3 -c "
import sys, json
for a in json.load(sys.stdin).get('assets', []):
    if a['name'] == 'debian-rootfs-${ARCH}.img':
        print(a['browser_download_url']); break
")"
    [[ -z "$URL" ]] && die "Asset tidak ditemukan. Cek: gh release list --repo $GITHUB_REPO"
    curl -fL --progress-bar "$URL" -o "$DEST"
fi

[[ -f "$DEST" ]] || die "Download gagal"
log "Done: $DEST ($(du -sh "$DEST" | cut -f1))"
