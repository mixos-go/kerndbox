/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __FAULTINFO_ARM64_H
#define __FAULTINFO_ARM64_H

/*
 * arm64 UML fault info.
 *
 * On arm64, the fault address comes from si_addr in siginfo_t (delivered
 * to stub_segv_handler). We do NOT have access to ESR_EL1 (syndrome bits)
 * or FAR_EL1 from userspace ptrace on modern kernels.
 *
 * fault_address: from siginfo->si_addr (FAR_EL1 equivalent)
 * error_code:    from siginfo->si_code (SEGV_MAPERR=1, SEGV_ACCERR=2, etc.)
 * trap_no:       always 0 (no trap number concept on arm64 UML)
 */
struct faultinfo {
	int error_code;		  /* si_code: SEGV_MAPERR, SEGV_ACCERR, etc. */
	unsigned long fault_address; /* si_addr */
	int trap_no;		  /* always 0 */
};

#define FAULT_WRITE(fi)		((fi).error_code == SEGV_ACCERR)
#define FAULT_ADDRESS(fi)	((fi).fault_address)

/*
 * All SIGSEGV faults delivered to the UML stub are data/instruction aborts
 * that the UML kernel can attempt to fix via page fault handling.
 * Alignment faults (SIGBUS, not SIGSEGV) never reach this path.
 * So all faults seen here are potentially fixable.
 */
#define SEGV_IS_FIXABLE(fi)	1

/*
 * PTRACE_FULL_FAULTINFO=1: UML uses get_skas_faultinfo() path, which
 * delivers SIGSEGV to the stub so stub_segv_handler fills in faultinfo
 * on the stub data page from siginfo_t.
 */
#define PTRACE_FULL_FAULTINFO	1

#endif /* __FAULTINFO_ARM64_H */
