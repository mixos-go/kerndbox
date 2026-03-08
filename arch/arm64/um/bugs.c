// SPDX-License-Identifier: GPL-2.0
/* arm64 UML: CPU bug checks and signal examination stubs */
#include <arch.h>
#include <sysdep/ptrace.h>

void arch_check_bugs(void)
{
}

void arch_examine_signal(int sig, struct uml_pt_regs *regs)
{
}
