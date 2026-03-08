// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/stub_segv.c
 *
 * Stub code mapped into every UML child process at STUB_CODE.
 * stub_segv_handler is installed as the SIGSEGV handler; it saves
 * fault info into the stub data page so the UML kernel can read it.
 */

#include <linux/unistd.h>
#include <sys/ucontext.h>
#include <signal.h>
#include <string.h>
#include <sysdep/stub.h>
#include <sysdep/faultinfo.h>
#include <sysdep/mcontext.h>
#include "stub-data.h"

/* Forward declarations to suppress -Wmissing-prototypes.
 * These are section-placed stubs, not called directly. */
void __attribute__((section(".stub"))) stub_segv(void);
void __attribute__((section(".stub"))) stub_end(void);


/*
 * stub_segv — minimal SVC stub.
 * Triggers a trap so the UML kernel thread wakes up on a page fault.
 */
void __attribute__ ((section (".stub"))) stub_segv(void)
{
	__asm__ __volatile__(
		"mov x8, %0\n"
		"svc #0\n"
		:
		: "i"(__NR_getpid)
		: "x8", "x0"
	);
}

/*
 * stub_segv_handler — SIGSEGV handler installed in the child process.
 * Runs at STUB_CODE; fills faultinfo on stub data page via GET_FAULTINFO_FROM_MC,
 * then calls trap_myself() to stop and let the UML kernel handle the fault.
 * Signature must match struct sigaction.sa_sigaction.
 */
void __attribute__ ((section (".stub")))
stub_segv_handler(int sig, siginfo_t *info, void *p)
{
	struct faultinfo *f = get_stub_data();
	ucontext_t *uc = p;

	GET_FAULTINFO_FROM_MC(*f, &uc->uc_mcontext);
	trap_myself();
}

void __attribute__ ((section (".stub"))) stub_end(void)
{
}
