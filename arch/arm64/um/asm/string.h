/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/asm/string.h
 *
 * Override arm64's native string.h for UML.
 *
 * arm64's real string.h declares __HAVE_ARCH_* for functions implemented in
 * arch/arm64/lib/*.[S] (NEON assembly). Those .S files are NOT compiled in UML
 * mode, so we must not claim to have those implementations — otherwise modules
 * would get undefined symbol errors.
 *
 * EXCEPTION: memcpy / memmove / memset
 * arch/um/os-Linux/user_syms.c already exports these (via libc) for all
 * non-x86 UML architectures (guarded by #ifndef __x86_64__).
 * We must tell lib/string.c NOT to compile its own copies, otherwise modpost
 * sees the symbol exported twice → fatal build error.
 *
 * All other string functions (strlen, strcmp, strchr, etc.) are left to
 * lib/string.c to provide — they are NOT exported by user_syms.c.
 */
#ifndef __UM_ASM_ARM64_STRING_H
#define __UM_ASM_ARM64_STRING_H

/*
 * Claim memcpy/memmove/memset so lib/string.c skips them.
 * Actual implementations come from libc via arch/um/os-Linux/user_syms.c.
 */
#define __HAVE_ARCH_MEMCPY
#define __HAVE_ARCH_MEMMOVE
#define __HAVE_ARCH_MEMSET

extern void *memcpy(void *dest, const void *src, __kernel_size_t n);
extern void *memmove(void *dest, const void *src, __kernel_size_t n);
extern void *memset(void *s, int c, __kernel_size_t n);

/* All other string functions: provided by lib/string.c (no NEON needed) */

#endif /* __UM_ASM_ARM64_STRING_H */
