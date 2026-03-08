# AGENT.md — UML arm64 Port (DevBox Project)

> **Baca file ini dulu sebelum menyentuh apapun.**
> File ini adalah "otak" project. Berisi semua konteks, keputusan desain,
> kesalahan yang sudah terjadi, dan status terkini.

---

## 1. Tujuan Project

**DevBox** — Android APK yang menjalankan distro Linux lengkap (Debian/Ubuntu)
di atas device Android **tanpa root** menggunakan **User Mode Linux (UML)**
yang di-port ke **ARM64**.

Target: alternatif lebih ringan dari QEMU, tanpa butuh KVM/root.

**Stack:**
```
Android App (Java/Kotlin)
    └── fork/exec → linux (UML binary, compiled ARCH=um SUBARCH=aarch64)
                        └── jalankan guest Linux di atas ptrace
```

---

## 2. Constraint Kritis (JANGAN DILANGGAR)

| Constraint | Alasan |
|---|---|
| **NO root** | Target: user biasa di Play Store |
| **NO KVM** | Tidak tersedia tanpa root |
| **NO PTRACE_SYSEMU** | Android SELinux blokir di non-root |
| **NO PTRACE_GETREGS/SETREGS** | Tidak ada di arm64 kernel |
| **NO symlink di /sdcard** | FAT/exFAT tidak support symlink |

---

## 3. Keputusan Desain Utama

### 3.1 Kenapa UML bukan QEMU?
- QEMU butuh KVM untuk performa acceptable → butuh root
- UML jalan murni di userspace via ptrace → no root needed
- UML sudah ada di kernel mainline, tinggal port ke arm64

### 3.2 PTRACE_SYSCALL Trick (pengganti PTRACE_SYSEMU)

Ini **inti dari seluruh port**. PTRACE_SYSEMU tidak ada di arm64 dan diblokir
SELinux. Solusinya tirukan proot:

```
PTRACE_SYSCALL → stop di syscall ENTRY
  → UML ganti syscall number ke __NR_getpid (harmless)
  → host kernel eksekusi → dapat ENOSYS (aman)
  → stop di syscall EXIT
  → UML inject return value yang benar
  → guest resume dengan hasil yang benar
```

State tracking pakai `at_syscall_entry` boolean (toggle entry/exit).

### 3.3 Register Access arm64

arm64 TIDAK punya `PTRACE_GETREGS`/`PTRACE_SETREGS`. Harus pakai:
- GP regs: `PTRACE_GETREGSET` dengan `NT_PRSTATUS` → `struct user_pt_regs`
- FP/SIMD: `PTRACE_GETREGSET` dengan `NT_PRFPREG` → `struct user_fpsimd_state`

### 3.4 arm64 Register Layout (gp[] array)

```
gp[0]  .. gp[30]  = x0 .. x30
gp[31]            = sp
gp[32]            = pc
gp[33]            = pstate

HOST_SP    = 31
HOST_PC    = 32
HOST_PSTATE = 33

Syscall: x8 = nr, x0-x5 = args, x0 = return value
```

### 3.5 FP/SIMD Layout (fp[] array)

```
struct user_fpsimd_state:
  __uint128_t vregs[32]  → 64 unsigned long (512 bytes)
  __u32 fpsr             → dalam ulong ke-64 (low 32 bit)
  __u32 fpcr             → dalam ulong ke-65 (low 32 bit)
  __u32 __reserved[2]

FP_SIZE = 66  (total unsigned long dalam array)
```

---

## 4. Struktur File Repo

```
.github/workflows/build.yml       ← CI: build kernel + rootfs + boot test
arch/
  arm64/
    Makefile.um                   ← build system entry point
    um/
      asm/          (20+ headers — UML overrides untuk arm64)
      os-Linux/     (7 C files + arm64_um_os.h)
      shared/sysdep/ (9 headers)
      *.c           (bugs, delay, mem, ptrace, signal, strrchr, stub_segv,
                     sys_call_table, syscalls, sysrq, task_size, tls, user-offsets)
      setjmp.S      ← kernel_setjmp / kernel_longjmp arm64 asm
      Kconfig, Makefile
  um/configs/arm64_defconfig      ← kernel config (Fase 1-3 configs)
build.sh                          ← local arm64 Docker build
scripts/
  build-debian-image.sh           ← CI build script (cp arch/ + apply patches)
  patches/uml-arm64/              ← 11 patches untuk existing kernel files
AGENT.md                          ← file ini
PATCHING-PHASE.md                 ← detail patch + roadmap
DEVBOX-ENGINE.md                  ← arsitektur app Android
```

---

## 5. Patches (scripts/patches/uml-arm64/)

| File | Target | Keterangan |
|---|---|---|
| 0001b | arch/arm64/Makefile | Tambah archheaders target → cpucap-defs.h |
| 0007 | arch/um/os-Linux/skas/process.c | arm64 compat + PTRACE_SYSCALL fallback |
| 0007b | arch/um/kernel/process.c | arm64 compat (JB_SP array index) |
| 0007c | arch/um/os-Linux/skas/process.c | jmpbuf arm64 |
| 0008 | arch/um/os-Linux/start_up.c | non-fatal sysemu check |
| 0008b | arch/um/os-Linux/start_up.c | no LDT on arm64 |
| 0009 | arch/um/os-Linux/registers.c | arm64 register compat |
| 0009b | arch/um/include/asm/cpufeature.h | CONFIG_X86 guard |
| 0009c | arch/um/kernel/um_arch.c | x86 guards + skas.h include |
| 0009d | arch/um/kernel/Makefile | capflags.o obj-$(CONFIG_X86) |
| 0009e | arch/um/kernel/{um_arch,process,ptrace}.c + skas/syscall.c | fix -Wmissing-prototypes |

---

## 6. Status Komponen

| Komponen | Status | Notes |
|---|---|---|
| Build system (Makefile.um, Kconfig) | ✅ Done | |
| arch headers (ptrace.h, elf.h, dll) | ✅ Done | |
| stub_segv.c | ✅ Done | |
| sys_call_table.c | ✅ Done | pragma suppress Wcast-function-type |
| sysdep headers | ✅ Done | JB_IP=11, JB_SP=12 |
| GP + FP register access | ✅ Done | GETREGSET/SETREGSET |
| setjmp.S (kernel_setjmp/longjmp) | ✅ Done | arm64 asm |
| delay.c (__const_udelay dll) | ✅ Done | pure C |
| strrchr.c (kernel_strrchr) | ✅ Done | #undef guard |
| mem.c (mmap_rnd_bits) | ✅ Done | value=18 |
| PTRACE_SYSCALL fallback | ✅ Done | pengganti SYSEMU |
| check_sysemu non-fatal | ✅ Done | |
| signal frame (rt_sigframe) | ✅ Done | |
| UPT_* macros, EXECUTE_SYSCALL | ✅ Done | |
| processor.h, defconfig | ✅ Done | Fase 2+3 configs |
| arch_do_signal, prctl, uaccess | ✅ Done | |
| asm/checksum.h (no hardware csum) | ✅ Done | redirect ke generic |
| asm/word-at-a-time.h (no MTE) | ✅ Done | redirect ke generic |
| **Compile + link bersih** | ✅ Done | 3.54MB binary, 0 error |
| **Warning bersih (0 warning)** | ✅ Done | semua 335 warning dibereskan |
| **Boot test di CI** | ✅ Done | busybox rootfs → DEVBOX_BOOT_OK |
| **Runtime boot actual** | ⏳ Belum ditest | perlu kernel-latest artifact |
| **Fase 2: namespace aktif** | ⏳ Defconfig siap | belum ditest |
| **Fase 3: Docker di UML** | ⏳ Defconfig siap | belum ditest |

---

## 7. Cara Build

```bash
# 1. Download kernel
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.74.tar.xz
tar -xf linux-6.12.74.tar.xz

# 2. Apply semua patches
cd linux-6.12.74
for p in /path/to/scripts/patches/uml-arm64/0*.patch; do
    patch -p1 --forward < "$p"
done

# 3. Copy arch files
cp -r /path/to/arch/arm64/um arch/arm64/um
cp arch/um/configs/arm64_defconfig .

# 4. Configure + Build
make ARCH=um SUBARCH=arm64 arm64_defconfig
make ARCH=um SUBARCH=arm64 -j$(nproc)

# 5. Binary ada di: ./linux (atau ./vmlinux)
```

---

## 8. Boot Test (CI)

Test di `.github/workflows/build.yml` — job `boot-test`:

```bash
# Apa yang dilakukan:
# 1. Buat minimal ext4 rootfs dengan busybox-static
# 2. Boot UML binary dengan rootfs itu
# 3. init = shell script yang print "DEVBOX_BOOT_OK" + poweroff
# 4. Grep output untuk DEVBOX_BOOT_OK → pass/fail

./linux-uml-aarch64 \
    ubd0=test-rootfs.img \
    root=/dev/ubda \
    mem=256M \
    con=fd:0,fd:1 \
    ssl=null quiet
```

---

## 9. Known Issues

### 9.1 CONFIG_PID_NS dimatikan
PID namespaces menyebabkan UML init crash (init process jadi PID 2 bukan PID 1).
Dimatikan di defconfig dengan komentar. Aktifkan kembali di Fase 2 setelah
ada test harness yang proper.

### 9.2 Patch Format
- **JANGAN** tulis `@@ -1,X +1,Y @@` untuk file baru → pakai `@@ -0,0 +1,N @@`
- **JANGAN** biarkan `@@ ... @@` dan content jadi satu baris
- Patch harus bisa `patch -p1 --forward` tanpa error

### 9.3 Makefile.um
- `SUBARCH_CFLAGS` → SALAH, harus `KBUILD_CFLAGS`
- `START_ADDR` → SALAH, harus `START`

### 9.4 Android Symlink
- Kernel source tidak bisa di-extract langsung di `/sdcard` (FAT)

---

## 10. Kalau Mau Lanjut dari Sini

1. Upload `devbox-uml-arm64.zip` ke chat baru
2. Upload `AGENT.md`, `PATCHING-PHASE.md`, `DEVBOX-ENGINE.md`
3. Bilang: *"Ini project UML arm64 port untuk DevBox Android. Baca AGENT.md dulu."*

AI akan langsung paham konteks penuh.
