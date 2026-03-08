// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/os-Linux/tls.c
 *
 * Set TPIDR_EL0 (arm64 TLS register) for a ptrace'd UML guest process.
 *
 * The host kernel stores TPIDR_EL0 in the guest's user_pt_regs and
 * restores it on every context switch. We write it via PTRACE_SETREGSET
 * with note type NT_ARM_TLS (0x401).
 *
 * This is called once per clone(CLONE_SETTLS) — i.e., every pthread_create().
 * Without it, all threads share TLS pointer 0 → immediate SIGSEGV.
 */

#include <errno.h>
#include <sys/ptrace.h>
#include <sys/uio.h>
#include <elf.h>          /* NT_ARM_TLS = 0x401 */
#include "os.h"

#ifndef NT_ARM_TLS
#define NT_ARM_TLS 0x401
#endif

int os_set_tls(int pid, unsigned long tls)
{
	struct iovec iov = {
		.iov_base = &tls,
		.iov_len  = sizeof(tls),
	};

	if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_ARM_TLS, &iov) < 0)
		return -errno;
	return 0;
}
