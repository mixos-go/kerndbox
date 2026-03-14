// SPDX-License-Identifier: GPL-2.0
/* C fallback — replaced by Rust (rust/src/signal.rs) */
#include <signal.h>
#include <string.h>
#include "arm64_um_os.h"
#include "os.h"
#include "skas/skas.h"

void remove_sigstack(void)
{
	stack_t ss = { .ss_flags = SS_DISABLE };
	sigaltstack(&ss, NULL);
}

void (*arch_get_signal_handler(int sig))(int, siginfo_t *, void *)
{
	(void)sig;
	return NULL;
}

void arch_do_signal(struct pt_regs *regs, int sig)
{
	(void)regs;
	(void)sig;
}
