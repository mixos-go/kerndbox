# kerndbox — Makefile
#
# ── Mulai di sini ─────────────────────────────────────────────────────────────
#   make menu         Menu interaktif lengkap
#   make help         Daftar semua shortcut
#
# ── Shortcut (non-interaktif) ─────────────────────────────────────────────────
#   make build        Build kernel (arch dari host)
#   make fetch        Download rootfs dari GitHub Releases
#   make test         Boot test
#   make patch-dry    Patch dry-run cepat (offline)
#   make patch-local  Patch dry-run + apply ke /tmp
#   make patch-up     Patch test vs kernel.org KERNEL_VER
#   make patch-full   Patch test lengkap (download + apply + makecheck)
#
# ── Pin rootfs ────────────────────────────────────────────────────────────────
#   make fetch BOOTSTRAP_TAG=bootstrap-v1.0.0

HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
  HOST_ARCH := aarch64
endif
ifeq ($(HOST_ARCH),aarch64)
  PROFILE  := arm64
  ARCH_OUT := arm64
else
  PROFILE  := x86
  ARCH_OUT := x86_64
endif

GITHUB_REPO   ?= mixos-go/kerndbox
GH_TOKEN      ?=
BOOTSTRAP_TAG ?=
KERNEL_VER    ?= 6.12.74
MIRROR        ?= https://cdn.kernel.org/pub/linux/kernel

export GITHUB_REPO GH_TOKEN BOOTSTRAP_TAG KERNEL_VER MIRROR

COMPOSE := docker compose --profile $(PROFILE)
RUN     := $(COMPOSE) run --rm
SCRIPTS := $(CURDIR)/scripts

.PHONY: help menu \
        build rootfs fetch test all shell image \
        patch patch-dry patch-local patch-up patch-full patch-ver \
        ptrace-fix clean cache-clean

help:
	@echo ""
	@echo "  kerndbox  ·  host: $(HOST_ARCH)  ·  kernel: $(KERNEL_VER)"
	@echo ""
	@echo "  ── Interaktif ────────────────────────────────────────────────────"
	@printf "  %-24s  %s\n" "make menu"          "Menu lengkap (kernel/rootfs/test/patch/shell)"
	@echo ""
	@echo "  ── Build shortcuts ───────────────────────────────────────────────"
	@printf "  %-24s  %s\n" "make build"         "Build kernel (host arch)"
	@printf "  %-24s  %s\n" "make rootfs"        "Build Debian rootfs"
	@printf "  %-24s  %s\n" "make fetch"         "Download rootfs dari Releases"
	@printf "  %-24s  %s\n" "make test"          "Boot test"
	@printf "  %-24s  %s\n" "make all"           "build → fetch → test"
	@printf "  %-24s  %s\n" "make shell"         "Shell di dev container"
	@echo ""
	@echo "  ── Patch shortcuts ───────────────────────────────────────────────"
	@printf "  %-24s  %s\n" "make patch-dry"     "Dry-run offline  (~5s)"
	@printf "  %-24s  %s\n" "make patch-local"   "Dry-run + apply ke /tmp  (~15s)"
	@printf "  %-24s  %s\n" "make patch-up"      "Download $(KERNEL_VER) + dry-run"
	@printf "  %-24s  %s\n" "make patch-full"    "Download + apply + makecheck"
	@printf "  %-24s  %s\n" "make patch-ver"     "Daftar semua patch"
	@echo ""
	@echo "  ── Options ───────────────────────────────────────────────────────"
	@printf "  %-24s  %s\n" "KERNEL_VER=6.13.0"  "Test versi kernel lain"
	@printf "  %-24s  %s\n" "BOOTSTRAP_TAG=..."   "Pin versi rootfs"
	@echo ""

# ── Interactive menu ──────────────────────────────────────────────────────────
menu:
	@bash $(SCRIPTS)/menu.sh

# ── Build ─────────────────────────────────────────────────────────────────────
image:
	docker build -t kerndbox:$(PROFILE) .

build: image
	$(RUN) dev-$(PROFILE) build

rootfs: image
	$(RUN) rootfs-$(PROFILE)

fetch: image
	$(RUN) dev-$(PROFILE) fetch

test: ptrace-fix
	$(RUN) test-$(PROFILE)

all: image
	$(RUN) dev-$(PROFILE) all

build-rootfs: build rootfs

shell: image
	$(RUN) dev-$(PROFILE)

# ── Patch shortcuts ───────────────────────────────────────────────────────────
patch-dry:
	@bash $(SCRIPTS)/test-patches-local.sh

patch-local:
	@bash $(SCRIPTS)/test-patches-local.sh --apply

patch-up:
	@bash $(SCRIPTS)/test-patches-upstream.sh \
		--kernel $(KERNEL_VER) --mirror $(MIRROR)

patch-full:
	@bash $(SCRIPTS)/test-patches-upstream.sh \
		--kernel $(KERNEL_VER) --mirror $(MIRROR) \
		--apply --makecheck

patch-ver:
	@echo ""
	@printf "  %-20s  %s\n" "Kernel" "$(KERNEL_VER)"
	@printf "  %-20s  %s\n" "Patches" \
		"$$(ls $(SCRIPTS)/patches/uml-arm64/0*.patch 2>/dev/null | wc -l | tr -d ' ')"
	@printf "  %-20s  %s\n" "Scratch" \
		"$$(find $(CURDIR)/arch/arm64 -type f 2>/dev/null | wc -l | tr -d ' ')"
	@echo ""
	@for p in $(SCRIPTS)/patches/uml-arm64/0*.patch; do \
		subj=$$(grep -m1 '^Subject:' "$$p" 2>/dev/null | sed 's/Subject: //'); \
		printf "  %-40s  %s\n" "$$(basename $$p)" "$$subj"; \
	done
	@echo ""

# Alias: make patch → masuk menu patch langsung
patch:
	@bash -c 'export KERNEL_VER=$(KERNEL_VER) MIRROR=$(MIRROR); \
	          source $(SCRIPTS)/menu.sh 2>/dev/null; sub_patch' \
	|| $(MAKE) patch-dry

# ── Misc ──────────────────────────────────────────────────────────────────────
ptrace-fix:
	@SCOPE=$$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo 0); \
	if [ "$$SCOPE" != "0" ]; then \
		echo "[kerndbox] Setting ptrace_scope=0..."; \
		sudo sysctl -w kernel.yama.ptrace_scope=0; \
	else \
		echo "[kerndbox] ptrace_scope=0 ✓"; \
	fi

clean:
	rm -rf output/

cache-clean:
	docker volume rm kerndbox-cache 2>/dev/null || true
