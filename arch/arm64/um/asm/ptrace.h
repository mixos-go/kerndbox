/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arm64/um/asm/ptrace.h — included as <asm/ptrace.h> for ARCH=um SUBARCH=arm64
 *
 * Must pull in ptrace-generic.h which defines struct pt_regs for UML.
 * The native arm64 ptrace.h is not suitable here.
 */
#ifndef __UM_PTRACE_ARM64_H
#define __UM_PTRACE_ARM64_H

/* Pull in UML common ptrace defs: struct pt_regs, EMPTY_REGS, etc. */
#include <asm/ptrace-generic.h>

/* arm64-specific extras not in ptrace-generic.h */
#define PT_FIX_EXEC_STACK(sp)  do { } while (0)

#define user_stack_pointer(regs)   UPT_SP(&(regs)->regs)
#define current_user_stack_pointer()   UPT_SP(&current->thread.regs.regs)
#define profile_pc(regs)           instruction_pointer(regs)

/* Return value register: x0 = gp[0] */
static inline long regs_return_value(struct pt_regs *regs)
{
	return UPT_SYSCALL_RET(&regs->regs);
}

/* Syscall return value / restart (used by arch/um/kernel/signal.c) */
#define PT_REGS_SYSCALL_RET(r)    UPT_SYSCALL_RET(&(r)->regs)
#define PT_REGS_ORIG_SYSCALL(r)   UPT_SYSCALL_NR(&(r)->regs)
#define PT_REGS_RESTART_SYSCALL(r) UPT_RESTART_SYSCALL(&(r)->regs)

/* Stack/IP for /proc and mm */
#define KSTK_EIP(tsk)  PT_REGS_IP(&(tsk)->thread.regs)
#define KSTK_ESP(tsk)  PT_REGS_SP(&(tsk)->thread.regs)

/* user_mode: true when pt_regs represents a userspace context */
#define user_mode(r)   UPT_IS_USER(&(r)->regs)

#define MAX_REG_OFFSET  (offsetof(struct uml_pt_regs, fp))

extern void arch_switch_to(struct task_struct *to);

#endif /* __UM_PTRACE_ARM64_H */
