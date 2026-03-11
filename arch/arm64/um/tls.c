// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/tls.c — TLS support for UML arm64
 *
 * arm64 uses TPIDR_EL0 for TLS (thread-local storage pointer).
 * In UML, the guest runs as a ptrace'd host process.
 * We set TPIDR_EL0 via PTRACE_SETREGSET NT_ARM_TLS on clone(CLONE_SETTLS).
 *
 * Without this: every pthread_create() leaves TLS = 0 → immediate crash.
 */

#include <linux/sched.h>
#include <sysdep/tls.h>
#include <os.h>
#include <skas.h>     /* userspace_pid[] */

extern int os_set_tls(int pid, unsigned long tls);

int arch_set_tls(struct task_struct *t, unsigned long tls)
{
	unsigned int cpu;
	int ret;

	/* Store in arch state for restore after context switch */
	t->thread.arch.tls = tls;

	/*
	 * Push to the ptrace'd host process immediately.
	 * userspace_pid[cpu] is the host PID of the UML guest process.
	 */
	cpu = task_cpu(t);
	ret = os_set_tls(userspace_pid[cpu], tls);
	if (ret)
		return ret;

	return 0;
}

void clear_flushed_tls(struct task_struct *task)
{
	task->thread.arch.tls = 0;
}

/*
 * arch_switch_to — called on every context switch to a new task.
 *
 * On arm64, TPIDR_EL0 (the TLS register) is NOT part of user_pt_regs,
 * so it is not saved/restored by the GP register save/restore in
 * skas/process.c. We must push it explicitly whenever we switch to a
 * different thread. This handles both the fork() inheritance case
 * (arch_copy_thread copied parent's tls to child) and the general
 * context switch case.
 */
void arch_switch_to(struct task_struct *to)
{
	if (to->mm)
		os_set_tls(userspace_pid[task_cpu(to)], to->thread.arch.tls);
}
