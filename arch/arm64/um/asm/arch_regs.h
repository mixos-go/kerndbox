/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __UM_ARCH_REGS_ARM64_H
#define __UM_ARCH_REGS_ARM64_H

/* asm-offsets.h is generated from this very compilation unit - guard against
 * circular inclusion when COMPILE_OFFSETS is defined (arch/um/kernel/asm-offsets.c) */
#ifndef COMPILE_OFFSETS
#include <generated/asm-offsets.h>
#endif

/*
 * arm64 UML host register file.
 * Mirrors struct user_pt_regs from <asm/ptrace.h> (the native arm64 ABI).
 * UML's ptrace layer fills this in via PTRACE_GETREGSET / NT_PRSTATUS.
 */
struct arch_regs {
	unsigned long long regs[31]; /* x0 .. x30 */
	unsigned long long sp;
	unsigned long long pc;
	unsigned long long pstate;
};

/* Accessors used by arch/um/kernel/regs.c */
#define REGS_IP(r)         ((r).pc)
#define REGS_SP(r)         ((r).sp)
#define REGS_SET_SYSCALL_RETURN(r, res) ((r).regs[0] = (res))

/* Syscall number is passed in x8 on arm64 */
#define REGS_SYSCALL_NR(r)  ((r).regs[8])

/* First 6 syscall args: x0..x5 */
#define REGS_SYSCALL_ARG1(r) ((r).regs[0])
#define REGS_SYSCALL_ARG2(r) ((r).regs[1])
#define REGS_SYSCALL_ARG3(r) ((r).regs[2])
#define REGS_SYSCALL_ARG4(r) ((r).regs[3])
#define REGS_SYSCALL_ARG5(r) ((r).regs[4])
#define REGS_SYSCALL_ARG6(r) ((r).regs[5])

/* pstate bit that indicates the process is in syscall-entry */
#define PSR_MODE_EL0t   0x00000000UL

static inline int is_syscall(unsigned long long pstate)
{
	/* UML skas mode sets this flag when intercepting a syscall */
	return 1;
}

#define HOST_TASK_REGS     offsetof(struct task_struct, thread.regs)
#define HOST_TASK_PID      offsetof(struct task_struct, pid)

/* Size of the register set when transferred via ptrace */
#define FRAME_SIZE         sizeof(struct arch_regs)

#endif /* __UM_ARCH_REGS_ARM64_H */
