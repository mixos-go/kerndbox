// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/user-offsets.c
 * Generates include/generated/user_constants.h via the offsets mechanism.
 * Defines HOST_* constants that encode arm64 register layout for UML.
 */
#include <stdio.h>
#include <stddef.h>
#include <signal.h>
#include <poll.h>
#include <sys/mman.h>
#include <asm/ptrace.h>
#include <asm/types.h>
#include <linux/kbuild.h>

/* suppress -Wmissing-prototypes */
void foo(void);

void foo(void)
{
	/*
	 * struct user_pt_regs layout (NT_PRSTATUS):
	 *   regs[31]  = x0..x30   (offsets 0..240, step 8)
	 *   sp        = offset 248 → index 31
	 *   pc        = offset 256 → index 32
	 *   pstate    = offset 264 → index 33
	 */
	DEFINE(HOST_SP,      offsetof(struct user_pt_regs, sp)     / sizeof(unsigned long));
	DEFINE(HOST_PC,      offsetof(struct user_pt_regs, pc)     / sizeof(unsigned long));
	DEFINE(HOST_PSTATE,  offsetof(struct user_pt_regs, pstate) / sizeof(unsigned long));

	/*
	 * struct user_fpsimd_state layout (NT_PRFPREG):
	 *   vregs[32]   = 512 bytes
	 *   fpsr + fpcr = 8 bytes
	 *   __reserved  = 8 bytes
	 *   Total: 528 bytes → 66 unsigned longs
	 */
	DEFINE(HOST_FP_SIZE, sizeof(struct user_fpsimd_state) / sizeof(unsigned long));

	DEFINE(UM_FRAME_SIZE, sizeof(struct user_pt_regs));

	DEFINE(UM_POLLIN,    POLLIN);
	DEFINE(UM_POLLPRI,   POLLPRI);
	DEFINE(UM_POLLOUT,   POLLOUT);

	DEFINE(UM_PROT_READ,  PROT_READ);
	DEFINE(UM_PROT_WRITE, PROT_WRITE);
	DEFINE(UM_PROT_EXEC,  PROT_EXEC);
}
