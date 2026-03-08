/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __SYSDEP_ARM64_PTRACE_H
#define __SYSDEP_ARM64_PTRACE_H

#include <sysdep/faultinfo.h>
#include <sysdep/ptrace_user.h>

/*
 * arm64 UML register accessors.
 *
 * gp[] layout (matches struct user_pt_regs / NT_PRSTATUS):
 *   gp[0]  .. gp[30] = x0 .. x30
 *   gp[31] = sp
 *   gp[32] = pc
 *   gp[33] = pstate
 *
 * HOST_SP / HOST_PC / HOST_PSTATE are defined in sysdep/ptrace_user.h.
 */

/* arm64: 34 GP registers (x0-x30=31, sp=31, pc=32, pstate=33) */
#define MAX_REG_NR  34
#define MAX_FP_NR   FP_SIZE

/*
 * arm64 UML register file, stored as array of unsigned longs.
 * Mirrors struct user_pt_regs (NT_PRSTATUS):
 *   gp[0..30] = x0..x30, gp[31]=sp, gp[32]=pc, gp[33]=pstate
 */
struct uml_pt_regs {
	unsigned long gp[MAX_REG_NR];
	unsigned long fp[MAX_FP_NR];
	struct faultinfo faultinfo;
	long syscall;
	int is_user;
};

#define EMPTY_UML_PT_REGS { }

/* true if register set represents a userspace context */
#define UPT_IS_USER(r)   ((r)->is_user)
#define UPT_FAULTINFO(r) (&(r)->faultinfo)

/* GP register direct index accessors */
#define REGS_X(r, n)   ((r)[(n)])

#define UPT_X(r, n)    REGS_X((r)->gp, (n))

/* Named aliases for commonly used registers */
#define UPT_SP(r)      ((r)->gp[HOST_SP])
#define UPT_PC(r)      ((r)->gp[HOST_PC])
#define UPT_PSTATE(r)  ((r)->gp[HOST_PSTATE])

/* Syscall register convention */
#define UPT_SYSCALL_NR(r)   ((r)->gp[8])       /* x8 = syscall number */
#define UPT_SYSCALL_RET(r)  ((r)->gp[0])        /* x0 = return value */

/* Restart syscall: move PC back 4 bytes (SVC #0 is 4 bytes on arm64) */
#define UPT_RESTART_SYSCALL(r) ((r)->gp[HOST_PC] -= 4)

/* Syscall arguments: x0..x5 */
#define UPT_SYSCALL_ARG1(r) ((r)->gp[0])
#define UPT_SYSCALL_ARG2(r) ((r)->gp[1])
#define UPT_SYSCALL_ARG3(r) ((r)->gp[2])
#define UPT_SYSCALL_ARG4(r) ((r)->gp[3])
#define UPT_SYSCALL_ARG5(r) ((r)->gp[4])
#define UPT_SYSCALL_ARG6(r) ((r)->gp[5])

/* IP / SP aliases used by arch/um/kernel/ */
#define UPT_IP(r)      UPT_PC(r)

/* PT_REGS_SP/IP/RESTART_SYSCALL/SYSCALL_NR defined by ptrace-generic.h */

/* raw gp[] array accessors (mirror x86 REGS_IP/REGS_SP) */
#define REGS_IP(r)  ((r)[HOST_PC])
#define REGS_SP(r)  ((r)[HOST_SP])

/* arm64: syscall return value in x0 = gp[0] */
#define PT_REGS_SET_SYSCALL_RETURN(r, res) \
	((r)->regs.gp[0] = (res))


extern void arch_init_registers(int pid);

#endif /* __SYSDEP_ARM64_PTRACE_H */
