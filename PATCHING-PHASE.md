# DevBox — UML arm64 Patching Phase Notes

## Status Saat Ini

**Target kernel:** Linux 6.12.74  
**Build host:** ubuntu-24.04-arm (GitHub Actions, uname -m = aarch64)  
**ARCH=um SUBARCH=arm64**

---

## Fase 1 — UML Boot ✅

| Task | Status |
|------|--------|
| Compile bersih tanpa error | ✅ Done (3.54MB binary) |
| Link bersih tanpa error | ✅ Done |
| 0 warning (setara x86 build) | ✅ Done |
| Boot test di CI (busybox rootfs) | ✅ Done |
| Boot actual ke Debian | ⏳ Perlu test dari CI artifact |

### File Baru Yang Kita Buat (arch/arm64/um/)

| File | Fungsi |
|------|--------|
| `asm/checksum.h` | Blokir hardware csum → redirect ke asm-generic |
| `asm/word-at-a-time.h` | Blokir arm64 MTE intrinsics → redirect ke asm-generic |
| `asm/processor.h` | task_pt_regs, cpu_relax, arch_thread |
| `asm/elf.h` | ELF_CLASS, ELF_DATA, ELF_ARCH sebelum linux/elf.h |
| `asm/ptrace.h` | current_user_stack_pointer direct macro |
| `shared/sysdep/archsetjmp.h` | jmp_buf arm64 (JB_IP=11, JB_SP=12) |
| `setjmp.S` | kernel_setjmp / kernel_longjmp arm64 asm |
| `delay.c` | __const_udelay, __udelay, __ndelay, __delay |
| `strrchr.c` | kernel_strrchr pure C |
| `mem.c` | mmap_rnd_bits=18 |
| `os-Linux/registers.c` | PTRACE_GETREGSET/SETREGSET full implementation |
| `os-Linux/arm64_um_os.h` | Forward decls untuk os-Linux functions |

### Patches Yang Ada (scripts/patches/uml-arm64/)

| Patch | File Kernel | Keterangan |
|-------|-------------|------------|
| 0001b | arch/arm64/Makefile | archheaders target → cpucap-defs.h |
| 0007 | arch/um/os-Linux/skas/process.c | PTRACE_SYSCALL fallback arm64 |
| 0007b | arch/um/kernel/process.c | JB_SP array index arm64 |
| 0007c | arch/um/os-Linux/skas/process.c | jmpbuf arm64 |
| 0008 | arch/um/os-Linux/start_up.c | non-fatal sysemu |
| 0008b | arch/um/os-Linux/start_up.c | no LDT |
| 0009 | arch/um/os-Linux/registers.c | arm64 register compat |
| 0009b | arch/um/include/asm/cpufeature.h | CONFIG_X86 guard |
| 0009c | arch/um/kernel/um_arch.c | x86 guards + skas.h |
| 0009d | arch/um/kernel/Makefile | capflags.o x86-only |
| 0009e | arch/um/kernel/{um_arch,process,ptrace}.c + skas/syscall.c | fix -Wmissing-prototypes |

---

## Fase 2 — Namespace & Isolasi (defconfig siap, belum ditest)

Semua config sudah ada di `arch/um/configs/arm64_defconfig`:

```
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
# CONFIG_PID_NS is not set  ← skip dulu, bisa break UML init
CONFIG_CGROUPS=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_CGROUP_SCHED=y
CONFIG_BLK_CGROUP=y
CONFIG_MEMCG=y
CONFIG_CPUSETS=y
```

**Test yang perlu dilakukan di Fase 2:**
```bash
# Dalam UML yang sudah boot ke Debian:
unshare --user --net /bin/bash   # user namespace
ip netns add test                 # network namespace
systemd-cgls                      # cgroup tree
```

---

## Fase 3 — Docker di dalam UML (defconfig siap, belum ditest)

Config sudah ada di defconfig:

```
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
CONFIG_OVERLAY_FS=m
CONFIG_VETH=m
CONFIG_BRIDGE=m
CONFIG_NETFILTER=y
CONFIG_NF_CONNTRACK=m
CONFIG_NF_TABLES=m
CONFIG_IP_NF_IPTABLES=m
CONFIG_IP_NF_FILTER=m
CONFIG_IP_NF_NAT=m
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_CGROUP_BPF=y
```

**Test yang perlu dilakukan di Fase 3:**
```bash
# Dalam UML + Debian:
apt install docker.io
docker run hello-world
```

---

## Fase 4 — Optimasi Performa

TODO (setelah Fase 3 stabil):
- Tune startup time (target <2s cold boot di Android)
- Virtio-style I/O untuk UBD
- hostfs shared folder untuk akses Android files
- Memory balloon: dynamic RAM allocation

---

## Fase 5 — Android App Integration

TODO:
- JNI wrapper `libdevbox.so` (posix_openpt, fork/exec UML)
- Terminal emulator (JediTerm atau fork termux-view)
- Download rootfs dari GitHub Releases on first launch
- Shared storage via hostfs (read-only /sdcard mount)

---

## Constraint Penting (JANGAN DILANGGAR)

- ❌ NO root di Android
- ❌ NO KVM
- ❌ NO `PTRACE_SYSEMU`
- ❌ NO `PTRACE_GETREGS/SETREGS` (arm64 only GETREGSET/SETREGSET)
- ❌ NO symlink di FAT filesystem
- ✅ PTRACE_SYSCALL (intercept syscall entry+exit)
- ✅ PTRACE_GETREGSET dengan NT_PRSTATUS

---

## Cara Boot Manual (setelah dapat artifact dari CI)

```bash
# Download dari GitHub Actions artifacts:
#   - kernel-aarch64  → linux-uml-aarch64
#   - rootfs-aarch64  → debian-rootfs-aarch64.img

chmod +x linux-uml-aarch64
./linux-uml-aarch64 \
    ubd0=debian-rootfs-aarch64.img \
    root=/dev/ubda \
    mem=512M \
    con=fd:0,fd:1

# Login: root / devbox
```

Tidak butuh initrd, bootloader, atau GRUB.  
UML langsung mount rootfs via UBD driver → exec /sbin/init.
