/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/shared/sysdep/tls.h
 *
 * arm64 UML TLS: uses TPIDR_EL0 register (set via PTRACE_SETREGSET NT_ARM_TLS).
 * No GDT/LDT involved (that is x86-specific).
 */
#ifndef __SYSDEP_ARM64_TLS_H
#define __SYSDEP_ARM64_TLS_H

/* Set TPIDR_EL0 for the ptrace'd guest process.
 * Called from os-Linux/tls.c after clone(CLONE_SETTLS). */
extern int os_set_tls(int pid, unsigned long tls);

#endif /* __SYSDEP_ARM64_TLS_H */
