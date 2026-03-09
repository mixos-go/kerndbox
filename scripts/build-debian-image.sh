#!/usr/bin/env bash
# build-debian-image.sh — Build Debian bookworm rootfs for DevBox
#
# Output: ./output/debian-rootfs-{arch}.img (sparse ext4)
#
# Usage:
#   ./scripts/build-debian-image.sh [aarch64|x86_64|all]

set -euo pipefail

ARCH="${1:-all}"
OUTPUT_DIR="$(pwd)/output"
DEBIAN_SUITE="bookworm"

mkdir -p "$OUTPUT_DIR"

log() { echo "[DevBox] $*"; }
die() { echo "[DevBox][ERROR] $*" >&2; exit 1; }

check_deps() {
    local missing=()
    for cmd in debootstrap mke2fs; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -gt 0 ]] && \
        die "Missing: ${missing[*]}. Install: sudo apt install debootstrap e2fsprogs"
}

build_rootfs() {
    local arch="$1"
    local deb_arch host_arch

    host_arch="$(uname -m)"
    [[ "$host_arch" == "arm64" ]] && host_arch="aarch64"

    case "$arch" in
        aarch64) deb_arch="arm64"  ;;
        x86_64)  deb_arch="amd64"  ;;
        *) die "Unknown arch: $arch" ;;
    esac

    local raw_img="$OUTPUT_DIR/debian-rootfs-${arch}.img"
    log "Building Debian ${DEBIAN_SUITE} rootfs for ${arch}..."

    # ── Step 1: debootstrap into a temp directory ──────────────────────────
    local work_dir
    work_dir="$(mktemp -d)"
    log "debootstrap stage: $work_dir"

    # Copy qemu static binary for cross-arch debootstrap only
    if [[ "$arch" != "$host_arch" ]]; then
        local qemu_bin="/usr/bin/qemu-${arch}-static"
        [[ -f "$qemu_bin" ]] || die "Cross-build needs $qemu_bin (install qemu-user-static)"
        cp "$qemu_bin" "$work_dir/usr/bin/" 2>/dev/null || true
    fi

    log "Running debootstrap (${deb_arch})..."
    debootstrap \
        --arch="$deb_arch" \
        --include="openssh-server,curl,socat,sudo,bash,zsh,coreutils,util-linux,net-tools,iproute2,procps,less,vim-tiny,ca-certificates,wget" \
        "$DEBIAN_SUITE" "$work_dir" "https://deb.debian.org/debian"

    log "Configuring rootfs..."
    echo "devbox" > "$work_dir/etc/hostname"

    cat > "$work_dir/etc/fstab" << 'FSTAB'
/dev/ubda   /       ext4    errors=remount-ro   0   1
proc        /proc   proc    defaults            0   0
sysfs       /sys    sysfs   defaults            0   0
tmpfs       /tmp    tmpfs   size=128M           0   0
FSTAB

    cat > "$work_dir/etc/network/interfaces" << 'NET'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
NET

    chroot "$work_dir" /bin/bash -c "echo 'root:devbox' | chpasswd"
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/'              "$work_dir/etc/ssh/sshd_config"
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' "$work_dir/etc/ssh/sshd_config"
    chroot "$work_dir" /bin/bash -c "systemctl enable ssh" 2>/dev/null || true

    log "Installing starship prompt..."
    chroot "$work_dir" /bin/bash -c "
        curl -fsSL https://starship.rs/install.sh -o /tmp/starship-install.sh
        chmod +x /tmp/starship-install.sh
        /tmp/starship-install.sh --yes --bin-dir /usr/local/bin
        rm -f /tmp/starship-install.sh
    " 2>/dev/null || log "WARNING: starship install failed — run manually"

    chroot "$work_dir" /bin/bash -c "chsh -s /bin/zsh root" 2>/dev/null || true

    cat > "$work_dir/root/.zshrc" << 'ZSHRC'
export TERM="xterm-256color"
export LANG="en_US.UTF-8"
export EDITOR="vim"
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE AUTO_CD EXTENDED_GLOB NO_BEEP
autoload -Uz compinit && compinit
bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias grep='grep --color=auto'
eval "$(starship init zsh)"
ZSHRC

    mkdir -p "$work_dir/mnt/devbox"

    # Remove qemu binary from rootfs before packing
    if [[ "$arch" != "$host_arch" ]]; then
        rm -f "$work_dir/usr/bin/qemu-${arch}-static"
    fi

    # ── Step 2: pack directory into ext4 image (no loop mount needed) ──────
    log "Creating ext4 image..."
    # Calculate size: used space + 30% headroom, minimum 1G
    local used_kb
    used_kb=$(du -sk "$work_dir" | cut -f1)
    local img_kb=$(( used_kb * 13 / 10 ))   # +30%
    (( img_kb < 1048576 )) && img_kb=1048576  # minimum 1G

    # mkfs.ext4 can write directly to a new image file
    truncate -s "${img_kb}K" "$raw_img"
    mke2fs -t ext4 -F -L "debian-devbox" \
        -d "$work_dir" \
        "$raw_img"

    rm -rf "$work_dir"
    log "Done: $raw_img ($(du -sh "$raw_img" | cut -f1) on disk)"
}

check_deps
log "=== Starting rootfs build for: ${ARCH} ==="

case "$ARCH" in
    aarch64) build_rootfs aarch64 ;;
    x86_64)  build_rootfs x86_64  ;;
    all)
        build_rootfs aarch64
        build_rootfs x86_64
        ;;
    *)
        die "Usage: $0 [aarch64|x86_64|all]"
        ;;
esac

log "=== Output ===" && ls -lh "$OUTPUT_DIR"/
