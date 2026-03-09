#!/bin/bash
# build-debian-image.sh - Build Debian bookworm rootfs for DevBox
#
# Output: ./output/debian-rootfs-{arch}.img (sparse ext4)
#
# Usage:
#   sudo ./scripts/build-debian-image.sh [aarch64|x86_64|all]

set -euo pipefail

log() { echo "[DevBox] $*"; }
die() { echo "[DevBox][ERROR] $*" >&2; exit 1; }
trap 'die "Script failed at line $LINENO"' ERR

log "=== build-debian-image.sh starting ==="
log "Running as: $(id)"
log "Working dir: $(pwd)"
log "Args: ${*:-<none>}"

ARCH="${1:-all}"
OUTPUT_DIR="$(pwd)/output"
DEBIAN_SUITE="bookworm"
HOST_ARCH="$(uname -m)"
[ "$HOST_ARCH" = "arm64" ] && HOST_ARCH="aarch64"

log "ARCH=$ARCH  HOST_ARCH=$HOST_ARCH"
mkdir -p "$OUTPUT_DIR"

check_deps() {
    local missing=()
    for cmd in debootstrap mke2fs; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    # qemu-aarch64-static needed only for cross-build (aarch64 on x86_64 host)
    if [ "$HOST_ARCH" = "x86_64" ] && [ "$ARCH" != "x86_64" ]; then
        [ -f "/usr/bin/qemu-aarch64-static" ] || missing+=("qemu-user-static")
    fi
    [ ${#missing[@]} -gt 0 ] && \
        die "Missing tools: ${missing[*]} -- run: apt install debootstrap e2fsprogs qemu-user-static binfmt-support"
    log "Deps OK: debootstrap=$(command -v debootstrap) mke2fs=$(command -v mke2fs)"
    mke2fs -V 2>&1 | head -1 | sed 's/^/[DevBox] /'
}

build_rootfs() {
    local arch="$1"
    local deb_arch

    case "$arch" in
        aarch64) deb_arch="arm64" ;;
        x86_64)  deb_arch="amd64" ;;
        *) die "Unknown arch: $arch" ;;
    esac

    local raw_img="$OUTPUT_DIR/debian-rootfs-${arch}.img"
    log "Building Debian $DEBIAN_SUITE rootfs for $arch (deb_arch=$deb_arch)"
    log "Output: $raw_img"

    # Step 1: debootstrap into temp dir
    local work_dir
    work_dir="$(mktemp -d /tmp/devbox-rootfs-XXXXXX)"
    log "Work dir: $work_dir"

    # Copy qemu only for cross-arch builds
    if [ "$arch" != "$HOST_ARCH" ]; then
        local qemu_bin="/usr/bin/qemu-${arch}-static"
        [ -f "$qemu_bin" ] || die "Cross-build needs $qemu_bin -- install qemu-user-static"
        mkdir -p "$work_dir/usr/bin"
        cp "$qemu_bin" "$work_dir/usr/bin/"
        log "Copied $qemu_bin for cross-build"
    fi

    log "Running debootstrap ($deb_arch)..."
    debootstrap \
        --arch="$deb_arch" \
        --include="openssh-server,curl,socat,sudo,bash,zsh,coreutils,util-linux,net-tools,iproute2,procps,less,vim-tiny,ca-certificates,wget" \
        "$DEBIAN_SUITE" "$work_dir" "https://deb.debian.org/debian"
    log "debootstrap done"

    # Step 2: configure rootfs
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
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' \
        "$work_dir/etc/ssh/sshd_config"
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' \
        "$work_dir/etc/ssh/sshd_config"
    chroot "$work_dir" /bin/bash -c "systemctl enable ssh" 2>/dev/null || true

    log "Installing starship (optional)..."
    chroot "$work_dir" /bin/bash -c "
        curl -fsSL https://starship.rs/install.sh -o /tmp/starship.sh
        chmod +x /tmp/starship.sh
        /tmp/starship.sh --yes --bin-dir /usr/local/bin
        rm -f /tmp/starship.sh
    " 2>/dev/null || log "WARNING: starship skipped (non-fatal)"

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

    # Remove qemu binary from rootfs
    [ "$arch" != "$HOST_ARCH" ] && rm -f "$work_dir/usr/bin/qemu-${arch}-static" || true

    # Step 2b: install kernel modules directly into the rootfs tree.
    # Modules must match the running kernel version — always build kernel first,
    # then rootfs. Pass the tarball path via env:
    #   MODULES_TAR_AARCH64=./output/modules-arm64.tar.gz
    #   MODULES_TAR_X86_64=./output/modules-x86_64.tar.gz
    local arch_upper
    arch_upper="$(echo "$arch" | tr '[:lower:]' '[:upper:]' | tr - _)"
    local modules_tar="${!MODULES_TAR_${arch_upper}:-${MODULES_TAR:-}}"

    if [ -n "$modules_tar" ] && [ -f "$modules_tar" ]; then
        local ko_count
        ko_count="$(tar -tzf "$modules_tar" | grep -c '\.ko$' || true)"
        log "Installing $ko_count kernel modules into rootfs..."
        tar -xzf "$modules_tar" -C "$work_dir"
        local kver
        kver="$(ls "$work_dir/lib/modules/" 2>/dev/null | head -1)"
        if [ -n "$kver" ]; then
            log "Running depmod for $kver..."
            chroot "$work_dir" /sbin/depmod -a "$kver" 2>/dev/null || \
                depmod -b "$work_dir" "$kver" 2>/dev/null || \
                log "WARNING: depmod failed (non-fatal)"
        fi
        log "Modules installed: /lib/modules/$kver/ ✓"
    else
        log "No modules tarball set — /lib/modules/ will be empty."
        log "  Set: MODULES_TAR_${arch_upper}=<path-to-modules-${arch}.tar.gz>"
    fi

    # Step 3: pack into ext4 image via mke2fs -d (no loop mount needed)
    log "Calculating image size..."
    local used_kb
    used_kb="$(du -sk "$work_dir" | cut -f1)"
    local img_kb=$(( used_kb * 13 / 10 ))
    [ "$img_kb" -lt 1048576 ] && img_kb=1048576
    log "Used: ${used_kb}KB  Image: ${img_kb}KB"

    log "Creating ext4 image..."
    truncate -s "${img_kb}K" "$raw_img"
    mke2fs -t ext4 -F -L "debian-devbox" -d "$work_dir" "$raw_img"

    log "Cleaning up..."
    rm -rf "$work_dir"

    log "Done: $raw_img ($(du -sh "$raw_img" | cut -f1))"
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

log "=== Done ==="
ls -lh "$OUTPUT_DIR"/
