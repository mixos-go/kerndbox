# kerndbox — Build & Test Environment
#
# UML CANNOT be cross-compiled. Always build natively:
#   arm64  → docker buildx build --platform linux/arm64  -t kerndbox .
#   x86_64 → docker buildx build --platform linux/amd64  -t kerndbox .
#
# Usage (interactive):
#   docker run --rm -it --privileged \
#     --security-opt seccomp=unconfined \
#     -v $(pwd):/workspace \
#     -v kerndbox-cache:/cache \
#     kerndbox bash
#
# Inside container:
#   scripts/build-arm64.sh   (or build-x86.sh)
#   scripts/fetch-rootfs.sh
#   scripts/run-test.sh

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# ── Build dependencies ────────────────────────────────────────────────────────
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      # kernel build essentials
      build-essential \
      flex \
      bison \
      libssl-dev \
      libelf-dev \
      bc \
      # source fetch + misc
      curl \
      wget \
      git \
      patch \
      xz-utils \
      ca-certificates \
      # boot test helpers
      file \
      # rootfs build
      debootstrap \
      qemu-user-static \
      binfmt-support \
      e2fsprogs \
      # GitHub CLI (for rootfs download from releases)
      gh \
    && rm -rf /var/lib/apt/lists/*

# Install gh CLI if not available from apt
# Fallback: manual install
RUN command -v gh >/dev/null 2>&1 || ( \
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
      chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
      apt-get update -qq && \
      apt-get install -y --no-install-recommends gh && \
      rm -rf /var/lib/apt/lists/* \
    )

# ── Persistent cache volume mount point ──────────────────────────────────────
# Mount a named volume here to cache kernel source tarballs across runs:
#   -v kerndbox-cache:/cache
RUN mkdir -p /cache /workspace/output

# ── UML host utilities ────────────────────────────────────────────────────────
# uml_switch is built from the same kernel source during the build step
# (make tools/uml) — see build-arm64.sh / build-x86.sh.
# Output is packaged as uml-tools-arm64.tar.gz / uml-tools-x86_64.tar.gz
# and extracted here at runtime via the entrypoint from the kernel release.
#
# The old 2007-era prebuilt uml-utilities_arm64.deb is no longer used.

# ── Symlink cache into /tmp so build scripts find tarballs ──────────────────
# build-arm64.sh and build-x86.sh download to /tmp/linux-*.tar.xz
RUN ln -s /cache /tmp/kernel-cache

WORKDIR /workspace

COPY scripts/entrypoint.sh /usr/local/bin/kerndbox-entrypoint
RUN chmod +x /usr/local/bin/kerndbox-entrypoint

ENTRYPOINT ["/usr/local/bin/kerndbox-entrypoint"]
CMD ["help"]
