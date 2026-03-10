# kerndbox — Makefile
#
# Flow utama:
#   make all      build kernel → download rootfs → boot test
#
# Step per step:
#   make build    Build UML kernel + modules
#   make fetch    Download rootfs dari GitHub Releases (latest stable)
#   make test     Boot test
#   make shell    Shell interaktif di container
#
# Pin versi rootfs:
#   make fetch BOOTSTRAP_TAG=bootstrap-v1.0.0
#
# Prerequisite sekali di host:
#   sudo sysctl -w kernel.yama.ptrace_scope=0

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

export GITHUB_REPO
export GH_TOKEN
export BOOTSTRAP_TAG

COMPOSE := docker compose --profile $(PROFILE)
RUN     := $(COMPOSE) run --rm

.PHONY: help build rootfs fetch test all shell image clean cache-clean ptrace-fix

help:
	@echo ""
	@echo "  kerndbox — UML kernel build & test"
	@echo ""
	@echo "  Host: $(HOST_ARCH)  →  output: kernel-$(ARCH_OUT), modules-$(ARCH_OUT).tar.gz"
	@echo "  Repo: $(GITHUB_REPO)"
	@echo ""
	@echo "  Commands:"
	@echo "    make all          build → fetch → test"
	@echo "    make build        Build UML kernel + modules"
	@echo "    make rootfs       Build Debian rootfs locally (bakes in modules)"
	@echo "    make build-rootfs Build kernel then rootfs in one shot"
	@echo "    make fetch        Download rootfs (latest stable release)"
	@echo "    make test         Boot test"
	@echo "    make shell        Shell interaktif di container"
	@echo ""
	@echo "  Options:"
	@echo "    BOOTSTRAP_TAG=bootstrap-v1.0.0   Pin ke versi rootfs spesifik"
	@echo "    GITHUB_REPO=other/repo           Override repo"
	@echo ""
	@echo "  Misc:"
	@echo "    make image        Build Docker image saja"
	@echo "    make ptrace-fix   Set ptrace_scope=0 di host (wajib untuk test)"
	@echo "    make clean        Hapus output/"
	@echo "    make cache-clean  Hapus Docker volume cache tarball kernel"
	@echo ""

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
