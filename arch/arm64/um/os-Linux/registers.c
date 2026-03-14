// SPDX-License-Identifier: GPL-2.0
/* C fallback — replaced by Rust (rust/src/ptrace.rs) when libarm64_um_os.a available */
#include <errno.h>
#include <string.h>
#include <sys/ptrace.h>
#include <sys/uio.h>
#include <elf.h>
#include <registers.h>
#include <os.h>
#include <sysdep/ptrace.h>
#include "arm64_um_os.h"
#include <sys/wait.h>
#include <signal.h>
#include <asm/unistd.h>
#include <skas.h>
#include "internal.h"

#ifndef NT_PRSTATUS
# define NT_PRSTATUS 1
#endif
#ifndef NT_PRFPREG
# define NT_PRFPREG 2
#endif

int save_registers(int pid, struct uml_pt_regs *regs)
{
	struct iovec iov = { regs->gp, sizeof(regs->gp) };
	if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
		return -errno;
	return 0;
}

int restore_registers(int pid, struct uml_pt_regs *regs)
{
	struct iovec iov = { regs->gp, sizeof(regs->gp) };
	if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
		return -errno;
	return 0;
}

int ptrace_getregs(long pid, unsigned long *regs_out)
{
	struct iovec iov = { regs_out, 34 * sizeof(unsigned long long) };
	if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
		return -errno;
	return 0;
}

int ptrace_setregs(long pid, unsigned long *regs_in)
{
	struct iovec iov = { (void *)regs_in, 34 * sizeof(unsigned long long) };
	if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
		return -errno;
	return 0;
}

int get_fp_registers(int pid, unsigned long *regs)
{
	struct iovec iov = { regs, 65 * sizeof(unsigned long) };
	if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRFPREG, &iov) < 0)
		return -errno;
	return 0;
}

int put_fp_registers(int pid, unsigned long *regs)
{
	struct iovec iov = { regs, 65 * sizeof(unsigned long) };
	if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRFPREG, &iov) < 0)
		return -errno;
	return 0;
}

void get_safe_registers(unsigned long *regs, unsigned long *fp_regs)
{
	if (regs)    memset(regs,    0, MAX_REG_NR * sizeof(unsigned long));
	if (fp_regs) memset(fp_regs, 0, FP_SIZE    * sizeof(unsigned long));
}

void arch_init_registers(int pid) { (void)pid; }

unsigned long get_thread_reg(int reg, jmp_buf *buf)
{
	/* arm64 glibc jmp_buf: JB_IP=11 (lr), JB_SP=12 */
	unsigned long *arr = (unsigned long *)buf;
	switch (reg) {
	case HOST_PC: return arr[JB_IP];
	case HOST_SP: return arr[JB_SP];
	default:
		printk(UM_KERN_ERR "get_thread_reg: unknown reg %d\n", reg);
		return 0;
	}
}

/* ── Syscall neutralization ────────────────────────────────────── */

#ifndef PTRACE_SET_SYSCALL
# define PTRACE_SET_SYSCALL 23
#endif

void arm64_neutralize_syscall(int pid)
{
	unsigned long long regs[34];
	struct iovec iov;

	/* Fast path: PTRACE_SET_SYSCALL (arm64-specific) */
	if (ptrace(PTRACE_SET_SYSCALL, pid, 0,
		   (void *)(unsigned long)__NR_getpid) == 0)
		return;

	/*
	 * Fallback: PTRACE_SETREGSET x8 = __NR_getpid.
	 * Works on all arm64 hosts including Graviton/GitHub Actions
	 * where PTRACE_SET_SYSCALL returns EIO.
	 */
	iov.iov_base = regs;
	iov.iov_len  = sizeof(regs);
	if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0) {
		printk(UM_KERN_ERR "arm64_neutralize_syscall: PTRACE_GETREGSET failed: %d\n",
		       errno);
		fatal_sigsegv();
		return;
	}
	regs[8] = __NR_getpid;  /* x8 = syscall number register */
	iov.iov_len = sizeof(regs);
	if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0) {
		printk(UM_KERN_ERR "arm64_neutralize_syscall: PTRACE_SETREGSET failed: %d\n",
		       errno);
		fatal_sigsegv();
	}
}

/* ── Startup ptrace check ────────────────────────────────────────── */

void arm64_check_ptrace(void)
{
	int pid, n, status;
	unsigned long long regs[34];
	struct iovec iov;
	unsigned long nr;
	int found = 0;

	os_info("Checking ptrace syscall modification (arm64 PTRACE_SET_SYSCALL)...");
	pid = start_ptraced_child();

	if (ptrace(PTRACE_SETOPTIONS, pid, 0,
		   (void *)PTRACE_O_TRACESYSGOOD) < 0)
		fatal_perror("arm64_check_ptrace: PTRACE_SETOPTIONS failed");

	while (1) {
		if (ptrace(PTRACE_SYSCALL, pid, 0, 0) < 0)
			fatal_perror("arm64_check_ptrace: PTRACE_SYSCALL failed");

		CATCH_EINTR(n = waitpid(pid, &status, WUNTRACED));
		if (n < 0)
			fatal_perror("arm64_check_ptrace: waitpid failed");

		if (!WIFSTOPPED(status)) {
			if (found && WIFEXITED(status) && WEXITSTATUS(status) == 0)
				break;
			fatal("arm64_check_ptrace: unexpected exit 0x%x\n", status);
		}
		if (WSTOPSIG(status) != (SIGTRAP | 0x80))
			continue;
		if (found)
			continue;

		iov.iov_base = regs;
		iov.iov_len  = sizeof(regs);
		if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
			fatal_perror("arm64_check_ptrace: PTRACE_GETREGSET failed");

		nr = regs[8];
		if (nr == __NR_getpid) {
			if (ptrace(PTRACE_SET_SYSCALL, pid, 0,
				   (void *)(unsigned long)__NR_getppid) < 0) {
				/*
				 * Non-fatal — PTRACE_SET_SYSCALL unavailable on
				 * some VM environments (Graviton, GitHub Actions).
				 * arm64_neutralize_syscall uses PTRACE_SETREGSET fallback.
				 */
				non_fatal("arm64_check_ptrace: PTRACE_SET_SYSCALL unavailable"
					  " (%s) — using PTRACE_SETREGSET fallback\n",
					  strerror(errno));
				stop_ptraced_child(pid, 0);
				return;
			}
			found = 1;
		}
	}
	os_info("OK\n");
	stop_ptraced_child(pid, 0);
}
