/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __PTRACE_USER_ARM64_H
#define __PTRACE_USER_ARM64_H

#include <generated/user_constants.h>

/*
 * arm64 ptrace register layout offsets.
 * Registers are accessed via PTRACE_GETREGSET/NT_PRSTATUS (struct user_pt_regs).
 * Layout: regs[0..30], sp, pc, pstate — all 8 bytes each.
 */

/* Byte offset of each field within struct user_pt_regs */
#define PT_OFFSET(r)       ((r) * sizeof(unsigned long long))

/* x8 holds the syscall number on arm64 */
#define PT_SYSCALL_NR(regs)        ((regs)[8])
#define PT_SYSCALL_NR_OFFSET       PT_OFFSET(8)

/* x0 holds the return value */
#define PT_SYSCALL_RET_OFFSET      PT_OFFSET(0)

/* Index aliases */
#define HOST_SP      31   /* sp field index */
#define HOST_PC      32   /* pc field index */
#define HOST_PSTATE  33   /* pstate field index */

#define REGS_IP_INDEX  HOST_PC
#define REGS_SP_INDEX  HOST_SP

/* FP/SIMD register save area size in unsigned longs.
 * struct user_fpsimd_state: 32 x 128-bit (16 bytes each) + fpsr + fpcr
 * = 32*2 + 2 = 66 unsigned longs (64-bit).
 */
#define FP_SIZE  66

/*
 * PTRACE_SYSEMU is not available on arm64 (not implemented in Linux arm64).
 * UML on arm64 falls back to PTRACE_SYSCALL mode (two-stop per syscall).
 * These defines prevent compile errors from generic UML code that references
 * PTRACE_SYSEMU; the actual runtime path is selected in os-Linux/skas/process.c.
 */
#ifndef PTRACE_SYSEMU
#define PTRACE_SYSEMU            31
#endif
#ifndef PTRACE_SYSEMU_SINGLESTEP
#define PTRACE_SYSEMU_SINGLESTEP 32
#endif

#endif /* __PTRACE_USER_ARM64_H */
