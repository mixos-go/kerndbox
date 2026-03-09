/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __ARCHSETJMP_ARM64_H
#define __ARCHSETJMP_ARM64_H

/*
 * glibc aarch64 jmp_buf layout (from glibc sysdeps/aarch64/jmp_buf-layout.h):
 *   [0]  = x19  (callee-saved)
 *   ...
 *   [9]  = x28
 *   [10] = x29 (fp)
 *   [11] = x30 (lr) — this is the IP that longjmp returns to
 *   [12] = sp
 *   [13] = d8..d15 (FP regs, optional)
 *
 * UML uses JB_IP for the instruction pointer and JB_SP for the stack pointer
 * in new_thread() and switch_threads().
 */

/*
 * arm64 callee-saved registers for setjmp/longjmp.
 * Matches glibc aarch64 jmp_buf layout:
 *   [0..9]  = x19..x28  (callee-saved GPRs)
 *   [10]    = x29 (fp)
 *   [11]    = x30 (lr) — longjmp return address
 *   [12]    = sp
 *   [13..20]= d8..d15  (callee-saved FP regs)
 */
struct __jmp_buf {
	unsigned long x19, x20, x21, x22;
	unsigned long x23, x24, x25, x26;
	unsigned long x27, x28, fp, lr;
	unsigned long sp;
	unsigned long pad;
	unsigned long d8, d9, d10, d11;
	unsigned long d12, d13, d14, d15;
};

typedef struct __jmp_buf jmp_buf[1];

#define JB_IP 11  /* lr (return address) at offset 88 = index 11 */
#define JB_SP 12  /* sp at offset 96 = index 12 */

unsigned long get_thread_reg(int reg, jmp_buf *buf);

#endif /* __ARCHSETJMP_ARM64_H */
