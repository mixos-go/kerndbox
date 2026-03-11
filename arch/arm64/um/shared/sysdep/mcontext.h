/* SPDX-License-Identifier: GPL-2.0 */
/* arm64 UML mcontext helper */
#ifndef __UM_ARM64_SYSDEP_MCONTEXT_H
#define __UM_ARM64_SYSDEP_MCONTEXT_H

#include <sysdep/faultinfo.h>

extern void get_regs_from_mc(struct uml_pt_regs *, mcontext_t *);

/*
 * GET_FAULTINFO_FROM_MC — arm64 mcontext_t does NOT expose CR2/ERR/TRAPNO
 * at user level (unlike x86). Fault info is taken from siginfo_t->si_addr
 * directly in stub_segv_handler(). This macro is kept as a no-op so that
 * generic UML code that calls it compiles cleanly.
 *
 * stub_segv_handler fills faultinfo from siginfo_t, not mcontext_t.
 */
#define GET_FAULTINFO_FROM_MC(fi, mc)	do { (void)(mc); } while (0)

#endif
