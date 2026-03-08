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
ROOTFS_SIZE="4G"
DEBIAN_SUITE="bookworm"

mkdir -p "$OUTPUT_DIR"

log() { echo "[DevBox] $*"; }
die() { echo "[DevBox][ERROR] $*" >&2; exit 1; }

check_deps() {
    local missing=()
    for cmd in debootstrap; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    # mkfs.ext4 may be in /sbin (not always in PATH)
    if ! command -v mkfs.ext4 &>/dev/null && ! [ -x /sbin/mkfs.ext4 ]; then
        missing+=(mkfs.ext4)
    fi
    [[ ${#missing[@]} -gt 0 ]] && \
        die "Missing: ${missing[*]}. Install: sudo apt install debootstrap e2fsprogs"
}

# Resolve mkfs.ext4 path (may be in /sbin)
MKFS_EXT4="$(command -v mkfs.ext4 2>/dev/null || echo /sbin/mkfs.ext4)"

build_rootfs() {
    local arch="$1"
    local deb_arch qemu_arch

    case "$arch" in
        aarch64) deb_arch="arm64";  qemu_arch="aarch64" ;;
        x86_64)  deb_arch="amd64";  qemu_arch="" ;;
        *) die "Unknown arch: $arch" ;;
    esac

    local raw_img="$OUTPUT_DIR/debian-rootfs-${arch}.img"
    log "Building Debian ${DEBIAN_SUITE} rootfs for ${arch}..."

    truncate -s 4G "$raw_img"
    "$MKFS_EXT4" -F -L "debian-devbox" "$raw_img"

    local mnt; mnt=$(mktemp -d)
    sudo mount -o loop "$raw_img" "$mnt"

    [[ -n "$qemu_arch" ]] && \
        sudo cp "/usr/bin/qemu-${qemu_arch}-static" "$mnt/usr/bin/" 2>/dev/null || true

    log "Running debootstrap (${deb_arch})..."
    sudo debootstrap \
        --arch="$deb_arch" \
        --include="openssh-server,curl,socat,sudo,bash,zsh,coreutils,util-linux,net-tools,iproute2,procps,less,vim-tiny,ca-certificates,wget" \
        "$DEBIAN_SUITE" "$mnt" "https://deb.debian.org/debian"

    log "Configuring rootfs..."
    echo "devbox" | sudo tee "$mnt/etc/hostname" >/dev/null

    sudo tee "$mnt/etc/fstab" >/dev/null <<'FSTAB'
/dev/ubda   /       ext4    errors=remount-ro   0   1
proc        /proc   proc    defaults            0   0
sysfs       /sys    sysfs   defaults            0   0
tmpfs       /tmp    tmpfs   size=128M           0   0
FSTAB

    sudo tee "$mnt/etc/network/interfaces" >/dev/null <<'NET'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
NET

    sudo chroot "$mnt" /bin/bash -c "echo 'root:devbox' | chpasswd"
    sudo sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/'              "$mnt/etc/ssh/sshd_config"
    sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' "$mnt/etc/ssh/sshd_config"
    sudo chroot "$mnt" /bin/bash -c "systemctl enable ssh" 2>/dev/null || true

    log "Installing starship prompt..."
    sudo chroot "$mnt" /bin/bash -c "
        curl -sS https://starship.rs/install.sh -o /tmp/starship-install.sh
        chmod +x /tmp/starship-install.sh
        /tmp/starship-install.sh --yes --bin-dir /usr/local/bin
        rm -f /tmp/starship-install.sh
    " 2>/dev/null || log "WARNING: starship install failed — run manually"

    sudo chroot "$mnt" /bin/bash -c "chsh -s /bin/zsh root" 2>/dev/null || true

    sudo tee "$mnt/root/.zshrc" >/dev/null <<'ZSHRC'
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

    sudo mkdir -p "$mnt/mnt/devbox"

    [[ -n "$qemu_arch" ]] && sudo rm -f "$mnt/usr/bin/qemu-${qemu_arch}-static"
    sudo umount "$mnt"; rmdir "$mnt"

    log "Done: $raw_img ($(du -sh "$raw_img" | cut -f1) on disk)"
}

check_deps

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
