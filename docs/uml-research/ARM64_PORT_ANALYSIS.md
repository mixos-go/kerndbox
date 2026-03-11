# UML arm64 Port — Deep Pattern Analysis

**Date:** 2026-03-11  
**Kernel:** Linux 6.12.74  
**Reference:** arch/x86/um/ + uml-downloads archive (old SourceForge + kernel.org HOWTO v2)

---

## Overview: How UML Works (Modern, Kernel 5.x+)

```
UML process (host userspace)
│
├── tracing thread (UML kernel)
│     - ptrace()s the guest process
│     - intercepts syscalls, page faults
│     - executes virtual syscalls in kernel space
│     - maps/unmaps guest pages via stub_syscall_handler
│
└── guest process (child, ptraced)
      - runs actual guest userspace code
      - has two special pages mapped at STUB_CODE/STUB_DATA:
          STUB_CODE: contains stub_segv_handler + stub_syscall_handler
          STUB_DATA: contains struct stub_data (incl. struct faultinfo)
      - on SIGSEGV: stub_segv_handler fills faultinfo, calls brk/int3
      - on syscall: UML kernel intercepts and handles
```

**Syscall interception:**
- x86: `PTRACE_SYSEMU` — single stop at entry, host never executes syscall
- arm64: `PTRACE_SYSCALL` two-stop — entry + exit (getpid neutralization pattern)

---

## Bug 1 (P0): stub_segv.c — Wrong Section Name

**File:** `arch/arm64/um/stub_segv.c`

```c
// WRONG:
void __attribute__ ((section (".stub")))
stub_segv_handler(int sig, siginfo_t *info, void *p)

// CORRECT:
void __attribute__((__section__(".__syscall_stub")))
stub_segv_handler(int sig, siginfo_t *info, void *p)
```

**Why:** UML linker scripts (`uml.lds.S`, `dyn.lds.S`) only collect `.__syscall_stub*`
into the `.syscall_stub` section. `physmem` maps `.syscall_stub` to `STUB_CODE` in each
child process. With the wrong section name, `stub_segv_handler` is unreachable at
runtime → all page faults in guest crash UML.

**Fix:** Use `.__syscall_stub`. Also removed the unnecessary `stub_segv()` wrapper
(generic `arch/um/kernel/skas/stub.c::stub_syscall_handler` is already in
`.__syscall_stub` and handles the mmap/munmap stub machinery).

---

## Bug 2 (P0): GET_FAULTINFO_FROM_MC — arm64 has no CR2/TRAPNO

**File:** `arch/arm64/um/shared/sysdep/mcontext.h`

```c
// WRONG (old):
#define GET_FAULTINFO_FROM_MC(fi, mc) \
    do { (void)(mc); memset(&(fi), 0, sizeof(fi)); } while (0)

// CORRECT:
#define GET_FAULTINFO_FROM_MC(fi, mc)   do { (void)(mc); } while (0)
```

x86 reads `REG_CR2`, `REG_ERR`, `REG_TRAPNO` from `mcontext_t`. arm64's
`mcontext_t` exposes none of these. Fault info comes from `siginfo_t->si_addr`
and `siginfo_t->si_code` in the signal handler itself.

**Fix:** `stub_segv_handler` fills `faultinfo` directly from `siginfo_t`:
```c
f->fault_address = (unsigned long)info->si_addr;
f->error_code    = info->si_code;   // SEGV_MAPERR=1, SEGV_ACCERR=2
f->trap_no       = 0;
```

---

## Bug 3 (P0): skas/process.c — Two-Stop Syscall NR Lost

**File:** `arch/um/os-Linux/skas/process.c` (patch 0007)

### The Bug

In `userspace()`, generic code does:
```c
save_registers(pid, regs);    // gp[8] = real syscall NR ✓
...
UPT_SYSCALL_NR(regs) = -1;   // gp[8] = -1 ← clobbers it!
...
switch (sig):
case SIGTRAP + 0x80:
    saved_syscall_nr = UPT_SYSCALL_NR(regs);  // reads -1 ← WRONG
```

`saved_syscall_nr` is ALWAYS -1. The two-stop mechanism saves/restores the
wrong value. `handle_syscall()` receives syscall NR = -1 → -ENOSYS for every
guest syscall.

### Bug 3b: Args Overwritten

At entry stop: x0-x5 have the syscall arguments.
After neutralized `getpid` executes: x0 = getpid return value (PID).
At exit stop, `save_registers()` reads x0 = PID, not the original arg1.
`handle_syscall()` then sees wrong arg1.

### Fix

Capture `gp[8]` immediately after `save_registers()`, before the `-1` clobber:
```c
save_registers(pid, regs);
#ifdef __aarch64__
unsigned long arm64_pre_x8 = regs->gp[8];  // real NR before generic clobber
#endif
UPT_SYSCALL_NR(regs) = -1;
```

At entry stop, use `arm64_pre_x8` (not `UPT_SYSCALL_NR`), save x0-x5.
At exit stop, restore NR and x0-x5 before `handle_trap()`.

Use `PTRACE_SET_SYSCALL` (arm64-specific ptrace op 23) to neutralize the
syscall NR in-flight — changes ONLY x8 in tracee, no full register write.

### Why x86 Doesn't Have This Problem

x86 has `ORIG_AX` — a separate slot for the original syscall NR that is
NOT the same as `AX` (return value). `UPT_SYSCALL_NR(regs)` maps to
`ORIG_AX`, while `UPT_SYSCALL_RET` maps to `AX`. The generic `= -1` sets
`ORIG_AX = -1` which is fine because x86 with `PTRACE_SYSEMU` never needs
to save/restore — it's a single-stop operation.

arm64 has no `ORIG_X8`. The syscall NR register (x8) is the same register
used before and after a syscall. This is why `PT_SYSCALL_NR_OFFSET == PT_OFFSET(8)`
while `PT_SYSCALL_RET_OFFSET == PT_OFFSET(0)` — they differ, so the generic
end-of-iteration `PT_SYSCALL_NR(regs->gp) = -1` runs, setting x8 = -1.

---

## Bug 4 (P1): FAULT_WRITE — Wrong bit check

**File:** `arch/arm64/um/shared/sysdep/faultinfo.h`

```c
// WRONG (old):
#define FAULT_WRITE(fi) ((fi).error_code & 2)

// CORRECT:
#define FAULT_WRITE(fi) ((fi).error_code == SEGV_ACCERR)
```

`error_code` is now `si_code` (POSIX), not ESR bits. `SEGV_ACCERR` = 2 means
"access violation" (write to read-only page). `SEGV_MAPERR` = 1 means "address
not mapped" (read OR write). Using `& 2` accidentally still works for `SEGV_ACCERR`
but is semantically wrong.

---

## Correct Patterns: x86 vs arm64

| Component | x86 Pattern | arm64 Pattern | Status |
|-----------|------------|---------------|--------|
| Stub section | `.__syscall_stub` | `.__syscall_stub` | ✓ fixed |
| Fault info | `mcontext->gregs[REG_CR2]` | `siginfo->si_addr` | ✓ fixed |
| `GET_FAULTINFO_FROM_MC` | reads mc fields | no-op (done in handler) | ✓ fixed |
| Syscall interception | `PTRACE_SYSEMU` (1-stop) | `PTRACE_SYSCALL` (2-stop) | ✓ fixed |
| Syscall NR register | `ORIG_AX` (separate slot) | `x8` (same as before NR) | ✓ fixed |
| Arg registers | x0-x5 safe across 1-stop | x0 overwritten → save/restore | ✓ fixed |
| Neutralize syscall | `PTRACE_SYSEMU` skips it | `PTRACE_SET_SYSCALL` → getpid | ✓ fixed |
| GP register I/O | `PTRACE_GETREGS/SETREGS` | `PTRACE_GETREGSET/NT_PRSTATUS` | ✓ in patch |
| FP register I/O | `PTRACE_GETREGSET/NT_X86_XSTATE` | `PTRACE_GETREGSET/NT_PRFPREG` | ✓ correct |
| `trap_myself()` | `int3` (x86 breakpoint) | `brk #0` (arm64 breakpoint) | ✓ correct |
| `get_stub_data()` | `rsp & ~mask` | `sp & ~mask` | ✓ correct |
| `jmp_buf` IP field | `__rip` (index 7) | index 11 (lr / x30) | ✓ correct |
| `jmp_buf` SP field | `__rsp` (index 1) | index 12 (sp) | ✓ correct |
| Signal frame struct | `{ pretcode, uc, info, fpstate }` | `{ info, uc }` | ✓ arm64 ABI |
| FP in signal | `fpstate` ptr in sigcontext | `fpsimd_context` in `__reserved[]` | ✓ arm64 ABI |
| `SC_RESTART_SYSCALL` | PC -= 2 (int 0x80 = 2 bytes) | PC -= 4 (svc #0 = 4 bytes) | ✓ correct |
| `SEGV_IS_FIXABLE` | `trap_no == 14` (page fault) | always 1 (all SIGSEGV fixable) | ✓ fixed |
| `FAULT_WRITE` | `error_code & 2` (ESR bits) | `error_code == SEGV_ACCERR` | ✓ fixed |
| `EXECUTE_SYSCALL` | x0-x5 args via DI/SI/DX/R10/R8/R9 | x0-x5 args directly | ✓ same shape |
| vDSO syscall | `syscall` instruction | `svc #0` | ✓ correct |
| vDSO `time()` | `__NR_time` syscall | `clock_gettime(CLOCK_REALTIME)` | ✓ no __NR_time on arm64 |
| vDSO linker | `vdso.lds.S` (cpp preprocessed) | `vdso.lds` (plain, no cpp) | ✓ fixed |
| PHDR assignments | `:text` on all sections | `:text` on all sections | ✓ fixed |
| `ptrace_dump_regs` | `PTRACE_GETREGS` | `PTRACE_GETREGSET` | ✓ in patch |
| TLS | `arch_prctl(ARCH_SET_FS)` | `PTRACE_SETREGSET/NT_ARM_TLS` | ✓ correct |
| PAC keys | n/a | `prctl(PR_PAC_RESET_KEYS)` | ✓ correct |

---

## What the Archive Confirmed

1. **No vDSO in old UML** — vDSO was not part of UML until well after 2004.
   arm64 UML vDSO is genuinely new territory.

2. **x86-64 was the only non-i386 port** (2.6.4 era). Structure it established
   (`arch/um/sys-x86_64/`) is the template for our `arch/arm64/um/`.

3. **`PTRACE_SYSEMU` requirement** is explicitly called out in the porting guide
   as critical. arm64 lacking it is the defining challenge of this port.
   Our two-stop fallback is architecturally sound once the NR/args bugs are fixed.

4. **`frame.h` pattern** (signal restorer address) is architecture-specific.
   arm64 uses the `SA_RESTORER` path, so `setup_signal_stack_si` setting
   `regs->gp[30] = ksig->ka.sa.sa_restorer` is correct (LR = return address).

---

## Newly Found Bugs (Session 2)

### Bug 5 (P0): check_ptrace() fatal on arm64 host

**File:** `arch/um/os-Linux/start_up.c` (patch 0008)

`check_ptrace()` uses `PTRACE_PEEKUSER` and `PTRACE_POKEUSER` to read/modify
the syscall NR of a ptraced child. On x86, `PTRACE_PEEKUSER` with
`PT_SYSCALL_NR_OFFSET` reads `ORIG_AX`. On arm64 host (64-bit), neither
`PTRACE_PEEKUSER` nor `PTRACE_POKEUSER` work for GP registers — the kernel's
`arch_ptrace()` only handles `PTRACE_PEEKMTETAGS`/`PTRACE_POKEMTETAGS` and
falls through to `ptrace_request()` which has no `PEEKUSR`/`POKEUSR` case,
returning `EIO`.

**Effect:** `PTRACE_PEEKUSER` returns -1 (errno=EIO). Loop in `check_ptrace()`
never finds `__NR_getpid`, eventually child exits with wrong code, `fatal()`
called → UML never boots.

**Fix:** Replace `check_ptrace()` on arm64 with `arm64_check_ptrace()` which
uses `PTRACE_GETREGSET(NT_PRSTATUS)` to read `x8` (syscall NR) and
`PTRACE_SET_SYSCALL` (op 23) to atomically change the in-flight NR.

### Bug 6 (P0): handle_syscall clobbers x0 (arg1) with -ENOSYS

**File:** `arch/um/kernel/skas/syscall.c` (patch 0007d)

On x86: `arg1=RDI`, `return=RAX` — different registers, no conflict.
On arm64: `arg1=x0`, `return=x0` — **same register**.

`handle_syscall()` calls `PT_REGS_SET_SYSCALL_RETURN(regs, -ENOSYS)` which
sets `gp[0] = -ENOSYS`. This happens **before** `EXECUTE_SYSCALL()` reads
`UPT_SYSCALL_ARG1 = gp[0]`. Result: every guest syscall receives `-ENOSYS`
as its first argument, and `EXECUTE_SYSCALL` immediately returns `-ENOSYS`
for all syscalls.

**Fix:** On arm64, save `gp[0..5]` before `PT_REGS_SET_SYSCALL_RETURN`, then
restore immediately after. `EXECUTE_SYSCALL` then sees the original args.

```c
#ifdef __aarch64__
unsigned long arm64_args[6] = { r->gp[0], ..., r->gp[5] };
#endif
UPT_SYSCALL_NR(r) = PT_SYSCALL_NR(r->gp);
PT_REGS_SET_SYSCALL_RETURN(regs, -ENOSYS);
#ifdef __aarch64__
r->gp[0] = arm64_args[0]; /* ... r->gp[5] = arm64_args[5]; */
#endif
```

### Architecture: Why x86 doesn't have Bug 6

x86 `uml_pt_regs` has a **separate** `.syscall` field:
```c
// arch/x86/um/shared/sysdep/ptrace.h
#define UPT_SYSCALL_NR(r) ((r)->syscall)   // ← separate .syscall field
#define UPT_SYSCALL_RET(r) ((r)->gp[HOST_AX])  // ← AX register
#define UPT_SYSCALL_ARG1(r) ((r)->gp[HOST_DI]) // ← DI register
```

`PT_REGS_SET_SYSCALL_RETURN` sets `AX`. `EXECUTE_SYSCALL` reads `DI` as arg1.
No overlap. On arm64 **all three** (`NR`, `RET`, `ARG1`) overlap at different
points in `gp[0]`/`gp[8]`, requiring careful save/restore.

### Complete Verified Syscall Flow (arm64, two-stop)

```
ENTRY STOP:
  save_registers: gp[0]=arg1, gp[8]=__NR_write (real NR)
  arm64_pre_x8 = gp[8]                         ← before -1 clobber
  UPT_SYSCALL_NR = -1 (gp[8] = -1)             ← generic clobber
  arm64_saved_nr = arm64_pre_x8 = __NR_write
  arm64_saved_args[0..5] = gp[0..5]            ← save args
  PTRACE_SET_SYSCALL(__NR_getpid) → tracee
  arm64_at_entry = true
  PTRACE_SYSCALL → getpid runs in tracee

EXIT STOP:
  save_registers: gp[0]=PID (getpid result), gp[8]=__NR_getpid
  arm64_pre_x8 = __NR_getpid
  UPT_SYSCALL_NR = -1
  arm64_at_entry=true:
    arm64_at_entry = false
    gp[8] = arm64_saved_nr = __NR_write         ← restore NR
    gp[0..5] = arm64_saved_args[0..5]           ← restore args
    handle_trap() → handle_syscall():
      save arm64_args[0..5] = gp[0..5]          ← 0007d: re-save
      gp[0] = -ENOSYS                           ← SET_SYSCALL_RETURN
      gp[0..5] = arm64_args[0..5]               ← 0007d: restore
      EXECUTE_SYSCALL(__NR_write):
        gp[0]=fd, gp[1]=buf, gp[2]=len → CORRECT
      gp[0] = bytes_written                      ← real return value
  restore_registers: writes gp[] back to tracee
  PTRACE_SYSCALL → tracee resumes with x0=bytes_written
```

---

## Session v8: Deep Architecture Review (2026-03-11)

### Bug 7: get_safe_registers not zeroing fp_regs → garbage FPSIMD at exec

**File:** `arch/arm64/um/os-Linux/registers.c`

When `copy_thread()` or `flush_thread()` calls `get_safe_registers(gp, fp)`, the arm64 implementation zeroed `gp` but left `fp` untouched. On the next `userspace()` iteration, `put_fp_registers(pid, regs->fp)` sends this garbage to the tracee. Since arm64 gcc emits NEON instructions by default, every new process would immediately crash.

**Fix:** `if (fp_regs) memset(fp_regs, 0, FP_SIZE * sizeof(unsigned long));`

### Bug 8: TLS not inherited on fork → child TPIDR_EL0 = 0

**File:** `arch/arm64/um/asm/processor.h`

`arch_copy_thread()` was a no-op. Since TPIDR_EL0 is NOT in `user_pt_regs` (not part of the GP register file), the `memcpy` in `copy_thread()` does not copy it. The child starts with TLS=0 and segfaults on first TLS access.

**Fix:** `to->tls = from->tls;` in `arch_copy_thread`.

### Bug 9: TPIDR_EL0 not restored on context switch

**File:** `arch/arm64/um/ptrace.c` / `arch/arm64/um/tls.c`

`arch_switch_to()` was a no-op. On each context switch, the host ptrace state for TPIDR_EL0 retains the previous task's value.

**Fix:** `arch_switch_to()` in `tls.c` calls `os_set_tls(userspace_pid[cpu], to->thread.arch.tls)`. The duplicate no-op in `ptrace.c` was removed.

### Bug 10: elf_core_copy_task_fpregs calls x86-only save_i387_registers

**File:** `arch/um/kernel/process.c`

`elf_core_copy_task_fpregs()` calls `save_i387_registers()`, which is guarded by `#ifdef CONFIG_X86` (patch 0015). On arm64 this is a linker error.

**Fix:** Added `#ifdef CONFIG_X86 / #else` guard in `process.c`. arm64 uses `get_fp_registers()` via `NT_PRFPREG`.

### Bug 11: arch_prctl_defaults() never called → PAC keys corrupt ptrace

**File:** `arch/um/os-Linux/start_up.c`

`arch_prctl_defaults()` disables PAC keys so ptrace register reads are not corrupted by pointer authentication. It was implemented in `prctl.c` but never called.

**Fix:** Call it in `os_early_checks()` before `check_ptrace()`.

### Bug 12 (CRITICAL): arch_fixup uses absolute offset for arm64 relative extable

**File:** `arch/arm64/um/fault.c`

arm64 uses `ARCH_HAS_RELATIVE_EXTABLE`: `struct exception_table_entry { int insn, fixup; short type, data; }` with relative signed int offsets. The old `fault.c` redefined it with `unsigned long` absolute fields and used `fixup->fixup` directly as an address.

Result: every `copy_from/to_user` fault causes kernel panic (PC redirected to garbage address) instead of returning `-EFAULT`.

**Fix:**
```c
unsigned long abs_fixup = (unsigned long)&entry->fixup +
                          (unsigned long)(long)entry->fixup;
UPT_IP(regs) = abs_fixup;
```

---

## Summary: Total Confirmed P0 Bugs

| # | Bug | Component | Severity |
|---|-----|-----------|----------|
| 1 | stub_segv.c wrong section | stub_segv.c | P0: all page faults fail |
| 2 | GET_FAULTINFO_FROM_MC is no-op | mcontext.h | P0: faultinfo always 0 |
| 3 | PTRACE_GETREGS/SETREGS fail on arm64 | registers.c | P0: no register access |
| 4 | PTRACE_SYSEMU not supported | process.c | P0: no syscall intercept |
| 5 | check_ptrace uses PTRACE_POKEUSER | start_up.c | P0: UML won't boot |
| 6 | handle_syscall clobbers x0 (arg1) | syscall.c | P0: all syscalls fail |
| 7 | get_safe_registers: fp_regs garbage | registers.c | P0: every exec crashes |
| 8 | TLS not inherited on fork | processor.h | P0: every fork crashes |
| 9 | TPIDR_EL0 not restored on ctxsw | tls.c | P0: TLS wrong after switch |
| 10 | elf_core_copy_task_fpregs x86 only | process.c | P1: linker error |
| 11 | arch_prctl_defaults not called | start_up.c | P1: PAC key corruption |
| 12 | arch_fixup: wrong extable offset | fault.c | P0: every uaccess panics |
