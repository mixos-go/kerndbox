# kerndbox — Docker & DevContainer Setup

## Penting: UML Tidak Bisa Cross-Compile

UML kernel **harus di-build di native host** — arm64 binary butuh arm64 machine,
x86_64 binary butuh x86_64 machine.

```
arm64 kernel   → build di arm64 host  (MacBook M-series, AWS Graviton, dll)
x86_64 kernel  → build di x86_64 host (PC biasa, AMD/Intel)
```

---

## Prerequisites

### 1. Docker
```bash
curl -fsSL https://get.docker.com | sh
```

### 2. ptrace_scope = 0 (wajib untuk boot test)
```bash
# Temporary
sudo sysctl -w kernel.yama.ptrace_scope=0

# Permanent
echo 'kernel.yama.ptrace_scope = 0' | sudo tee /etc/sysctl.d/99-ptrace.conf
sudo sysctl -p /etc/sysctl.d/99-ptrace.conf
```

### 3. GitHub repo
```bash
export GITHUB_REPO=mixos-go/kerndbox   # sudah default, skip kalau tidak ganti
export GH_TOKEN=ghp_xxx                # optional
```

---

## Cara Pakai

### Option A: Docker Compose

```bash
# arm64 host
docker compose --profile arm64 run --rm dev-arm64 build   # build kernel
docker compose --profile arm64 run --rm dev-arm64 fetch   # download rootfs
docker compose --profile arm64 run --rm dev-arm64 test    # boot test
docker compose --profile arm64 run --rm dev-arm64 all     # semuanya sekaligus
docker compose --profile arm64 run --rm dev-arm64         # shell interaktif

# x86_64 host — ganti arm64 → x86
docker compose --profile x86 run --rm dev-x86 all
```

### Option B: Makefile (lebih simpel)
```bash
make all      # build → fetch → test
make build    # build kernel saja
make fetch    # download rootfs saja
make test     # boot test saja
make shell    # shell interaktif
```

### Option C: Docker Run Manual
```bash
docker build -t kerndbox .

docker run --rm -it --privileged \
  --security-opt seccomp=unconfined \
  -e GITHUB_REPO=mixos-go/kerndbox \
  -e GH_TOKEN=$GH_TOKEN \
  -v $(pwd):/workspace \
  -v kerndbox-cache:/cache \
  kerndbox all
```

### Option D: VS Code DevContainer
1. Install extension **Dev Containers**
2. Buka folder project → `Ctrl+Shift+P` → **Reopen in Container**
3. Di terminal:
   ```bash
   scripts/build-arm64.sh
   scripts/fetch-rootfs.sh
   scripts/run-test.sh
   ```

---

## Output Files

```
output/
  kernel-arm64              ← UML kernel binary (arm64)
  kernel-x86_64             ← UML kernel binary (x86_64)
  modules-arm64.tar.gz      ← Kernel modules (arm64)
  modules-x86_64.tar.gz     ← Kernel modules (x86_64)
  debian-rootfs-aarch64.img ← Rootfs dari GitHub Releases (modules sudah baked in)
  debian-rootfs-x86_64.img
  boot-arm64.log            ← Boot test log
```

---

## Download Rootfs dari Releases

Rootfs di-download dari GitHub Releases secara otomatis oleh `fetch-rootfs.sh`.

```bash
# Download latest stable (default)
scripts/fetch-rootfs.sh

# Pin ke versi spesifik
BOOTSTRAP_TAG=bootstrap-v1.0.0 scripts/fetch-rootfs.sh

# Download manual dengan gh CLI
gh release download bootstrap-v1.0.0 \
  --repo mixos-go/kerndbox \
  --pattern "debian-rootfs-aarch64.img"

# Download latest tanpa BOOTSTRAP_TAG (gh CLI otomatis ambil --latest release)
gh release download \
  --repo mixos-go/kerndbox \
  --pattern "debian-rootfs-aarch64.img"
```

---

## Versioning

Releases dibuat manual via **Actions → Run workflow**:

| Workflow | Tag yang dibuat | Label |
|---|---|---|
| Build Kernel | `kernel-v1.0.0` | latest / experimental |
| Build Rootfs | `bootstrap-v1.0.0` | latest / experimental |

- **latest** → `gh release download` tanpa `--tag` otomatis ambil ini
- **experimental** → harus specify tag eksplisit

Rootfs workflow meminta `kernel_tag` — gunakan tag kernel yang sudah publish,
misal `kernel-v1.0.0`. Modules dari kernel itu akan di-bake ke dalam rootfs.

---

## Troubleshooting

### "check_ptrace" / UML hang saat boot
```bash
# Di HOST (bukan di container):
sudo sysctl -w kernel.yama.ptrace_scope=0
cat /proc/sys/kernel/yama/ptrace_scope  # harus 0
```

### "operation not permitted"
Container harus jalan dengan `--privileged` atau:
```bash
--cap-add SYS_PTRACE --security-opt seccomp=unconfined
```

### Cache kernel tarball
Tarball kernel (~130MB) di-cache di Docker volume `kerndbox-cache`.
Download hanya sekali, build ulang langsung pakai cache.
```bash
# Lihat isi cache
docker run --rm -v kerndbox-cache:/cache ubuntu ls -lh /cache/
# Hapus cache
make cache-clean
```
