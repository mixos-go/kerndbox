// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/os-Linux/registers.c — host-side register access for UML arm64.
 */

#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/uio.h>
#include <ptrace_user.h>
#include <registers.h>
#include <sys/user.h>
#include <elf.h>
#include "os.h"
#include "arm64_um_os.h"
#include "registers.h"
#include "skas/skas.h"
#include <sysdep/ptrace_user.h>
#include <sysdep/ptrace.h>

/* Forward declarations — used by arch/um/os-Linux/skas/process.c */
int save_registers(int pid, struct uml_pt_regs *regs);
int restore_registers(int pid, struct uml_pt_regs *regs);
/* ── GP register access (struct user_pt_regs via NT_PRSTATUS) ─────────────── */

int save_registers(int pid, struct uml_pt_regs *regs)
{
	struct iovec iov = {
		.iov_base = regs->gp,
		.iov_len  = sizeof(regs->gp),
	};
	if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
		return -errno;
	return 0;
}

int restore_registers(int pid, struct uml_pt_regs *regs)
{
	struct iovec iov = {
		.iov_base = regs->gp,
		.iov_len  = sizeof(regs->gp),
	};
	if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
		return -errno;
	return 0;
}

/*
 * ptrace_getregs / ptrace_setregs — called by arch/um/os-Linux/registers.c
 * init_pid_registers(). On arm64 we route through GETREGSET.
 */
int ptrace_getregs(long pid, unsigned long *regs_out)
{
	struct iovec iov = {
		.iov_base = regs_out,
		.iov_len  = 34 * sizeof(unsigned long long),
	};
	if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
		return -errno;
	return 0;
}

int ptrace_setregs(long pid, unsigned long *regs_in)
{
	struct iovec iov = {
		.iov_base = regs_in,
		.iov_len  = 34 * sizeof(unsigned long long),
	};
	if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
		return -errno;
	return 0;
}

/* ── FP/SIMD register access (struct user_fpsimd_state via NT_PRFPREG) ──── */

int get_fp_registers(int pid, unsigned long *regs)
{
	struct iovec iov = {
		.iov_base = regs,
		.iov_len  = FP_SIZE * sizeof(unsigned long),
	};
	if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRFPREG, &iov) < 0)
		return -errno;
	return 0;
}

int put_fp_registers(int pid, unsigned long *regs)
{
	struct iovec iov = {
		.iov_base = regs,
		.iov_len  = FP_SIZE * sizeof(unsigned long),
	};
	if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRFPREG, &iov) < 0)
		return -errno;
	return 0;
}

/*
 * get_safe_registers — fill regs with a safe initial register state.
 *
 * Called by arch/um/os-Linux/skas/mem.c and arch/um/kernel/exec.c before
 * a new thread or exec starts. On x86, this copies the registers captured
 * at UML startup (exec_regs). On arm64 we zero GP regs — the caller will
 * set PC/SP before the thread actually runs.
 *
 * fp_regs is unused on arm64 UML: NEON/SIMD state is managed by the host
 * kernel, not by UML kernel code.
 */
void get_safe_registers(unsigned long *regs, unsigned long *fp_regs)
{
	memset(regs, 0, MAX_REG_NR * sizeof(unsigned long));
	/* fp_regs intentionally ignored — no NEON state in UML context */
}

/* ── arch_init_registers ─────────────────────────────────────────────────── */

void arch_init_registers(int pid)
{
	/*
	 * Nothing to probe — FP/SIMD is mandatory on ARMv8.
	 * SVE probing can be added here in future.
	 */
}

/* ── get_thread_reg — jmp_buf accessor for UML context switch ────────────── */

unsigned long get_thread_reg(int reg, jmp_buf *buf)
{
	switch (reg) {
	case HOST_PC:
		return ((unsigned long *)buf)[JB_IP];
	case HOST_SP:
		return ((unsigned long *)buf)[JB_SP];
	default:
		printk(UM_KERN_ERR "get_thread_reg: unknown reg %d\n", reg);
		return 0;
	}
}
