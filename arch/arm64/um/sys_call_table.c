// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/sys_call_table.c
 *
 * arm64 UML syscall table.
 *
 * arm64 uses the generic syscall table (asm-generic/unistd.h), unlike
 * x86 which has its own.  We just include the generic UML wrapper that
 * maps each __NR_* to the corresponding sys_* or um_* handler.
 *
 * Syscall convention on arm64:
 *   x8  = syscall number
 *   x0..x5 = arguments
 *   x0  = return value
 *
 * UML intercepts the SVC #0 instruction via ptrace SYSCALL-entry stop,
 * reads x8 to get the syscall number, dispatches through this table,
 * writes the result back to x0, then resumes the guest skipping the
 * actual SVC so the host kernel never sees it.
 */

#include <linux/syscalls.h>
#include <asm/unistd.h>

/* Suppress -Wcast-function-type: sys_call_ptr_t casts are inherent in the
 * UML syscall table design and cannot be avoided. Same as x86 UML. */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wcast-function-type"
typedef long (*sys_call_ptr_t)(const struct pt_regs *);
extern asmlinkage long sys_ni_syscall(void);

/* arm64 UML overrides: signal return and mmap */
asmlinkage long sys_rt_sigreturn(void);
asmlinkage long sys_mmap(unsigned long addr, unsigned long len,
			unsigned long prot, unsigned long flags,
			unsigned long fd, unsigned long off);

/* Discard compat variants — arm64 UML runs 64-bit guests only */
#undef __SYSCALL
#undef __SC_COMP
#undef __SC_3264
#define __SYSCALL(nr, sym)   [nr] = (sys_call_ptr_t)sym,
#define __SC_COMP(nr, sym, csym) __SYSCALL(nr, sym)
#define __SC_3264(nr, sym32, sym64) __SYSCALL(nr, sym64)

const sys_call_ptr_t sys_call_table[] = {
	[0 ... 500] = (sys_call_ptr_t)sys_ni_syscall,
#include <asm-generic/unistd.h>
};

#pragma GCC diagnostic pop
