// SPDX-License-Identifier: GPL-2.0
/*
 * arm64 UML TLS support.
 * arm64 uses TPIDR_EL0 for TLS, not GDT segments (x86).
 * The host kernel saves/restores TPIDR_EL0 via PTRACE_SETREGSET.
 */
#include <linux/sched.h>

void clear_flushed_tls(struct task_struct *task)
{
}

int arch_set_tls(struct task_struct *t, unsigned long tls)
{
	return 0;
}
