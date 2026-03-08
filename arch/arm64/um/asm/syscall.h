/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/asm/syscall.h
 * Override arm64/include/asm/syscall.h for UML. The native header assumes
 * baremetal pt_regs (syscallno, orig_x0 fields); UML uses uml_pt_regs.
 */
#ifndef __UM_ASM_ARM64_SYSCALL_H
#define __UM_ASM_ARM64_SYSCALL_H

#include <asm/syscall-generic.h>
#include <uapi/linux/audit.h>

typedef asmlinkage long (*sys_call_ptr_t)(const struct pt_regs *);

static inline int syscall_get_arch(struct task_struct *task)
{
	return AUDIT_ARCH_AARCH64;
}

#endif /* __UM_ASM_ARM64_SYSCALL_H */

