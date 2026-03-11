// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/stub_segv.c
 *
 * SIGSEGV stub handler mapped into every UML child at STUB_CODE.
 *
 * MUST use section ".__syscall_stub" — the UML linker scripts
 * (uml.lds.S / dyn.lds.S) only collect .__syscall_stub* into .syscall_stub,
 * which is what physmem maps into each child process.
 *
 * Fault info on arm64:
 *   - fault_address: from siginfo->si_addr  (FAR_EL1 equivalent)
 *   - error_code:    from siginfo->si_code  (SEGV_MAPERR/SEGV_ACCERR)
 *   - trap_no:       0 (no x86-style trap number on arm64)
 *
 * The struct faultinfo lives at the base of the stub data page and is
 * read by get_skas_faultinfo() in os-Linux/skas/process.c.
 */

#include <sysdep/stub.h>
#include <sysdep/faultinfo.h>
#include <sys/ucontext.h>
#include <signal.h>

void __attribute__((__section__(".__syscall_stub")))
stub_segv_handler(int sig, siginfo_t *info, void *p)
{
	struct faultinfo *f = get_stub_data();

	f->fault_address = (unsigned long)info->si_addr;
	f->error_code    = info->si_code;   /* SEGV_MAPERR=1, SEGV_ACCERR=2 */
	f->trap_no       = 0;

	trap_myself();
}
