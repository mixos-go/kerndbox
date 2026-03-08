/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/asm/syscall.h
 *
 * Overrides arm64/include/asm/syscall.h for UML.
 *
 * UML arm64 uses the same generic syscall calling convention as UML x86:
 * sys_call_ptr_t takes 6 unsigned longs (the syscall arguments).
 * This matches the actual prototype of all sys_*() functions in the kernel,
 * and avoids -Wcast-function-type which would indicate a real ABI mismatch.
 *
 * Native arm64 uses (const struct pt_regs *) wrappers — those are generated
 * by the syscall wrapper mechanism which UML bypasses entirely.
 */
#ifndef __UM_ASM_ARM64_SYSCALL_H
#define __UM_ASM_ARM64_SYSCALL_H

#include <asm/syscall-generic.h>
#include <uapi/linux/audit.h>

/* Match actual sys_*() prototype — same as UML x86_64 */
typedef asmlinkage long (*sys_call_ptr_t)(unsigned long, unsigned long,
					  unsigned long, unsigned long,
					  unsigned long, unsigned long);

static inline int syscall_get_arch(struct task_struct *task)
{
	return AUDIT_ARCH_AARCH64;
}

#endif /* __UM_ASM_ARM64_SYSCALL_H */
