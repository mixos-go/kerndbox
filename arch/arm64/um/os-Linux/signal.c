// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/os-Linux/signal.c - arm64-specific signal hooks for UML.
 * set_sigstack() is in arch/um/os-Linux/signal.c (generic).
 */

#include <signal.h>
#include "arm64_um_os.h"
#include <string.h>
#include <errno.h>
#include "os.h"
#include "skas/skas.h"

void remove_sigstack(void)
{
	stack_t ss = { .ss_flags = SS_DISABLE };
	sigaltstack(&ss, NULL);
}

void (*arch_get_signal_handler(int sig))(int, siginfo_t *, void *)
{
	return NULL;
}

void arch_do_signal(struct pt_regs *regs, int sig)
{
	/*
	 * arm64 UML: no arch-specific pre-processing needed.
	 * FP/SIMD state is already in regs->regs.fp[] via
	 * get_fp_registers() in skas/process.c at every guest entry.
	 */
}
