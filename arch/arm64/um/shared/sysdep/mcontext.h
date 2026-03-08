/* SPDX-License-Identifier: GPL-2.0 */
/* arm64 UML mcontext helper declarations */
#ifndef __UM_ARM64_SYSDEP_MCONTEXT_H
#define __UM_ARM64_SYSDEP_MCONTEXT_H

#include <sysdep/faultinfo.h>

extern void get_regs_from_mc(struct uml_pt_regs *, mcontext_t *);

/*
 * arm64 mcontext_t has no fault info fields (no cr2/err/trapno).
 * Fault address comes from si_addr in the siginfo_t instead.
 * We leave faultinfo zeroed here; os-Linux/signal.c fills it from siginfo.
 */
#define GET_FAULTINFO_FROM_MC(fi, mc) \
	do { (void)(mc); memset(&(fi), 0, sizeof(fi)); } while (0)

#endif
