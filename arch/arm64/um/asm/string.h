/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * arch/arm64/um/asm/string.h
 *
 * In native arm64, string functions (strlen, strcmp, strchr, memcmp, etc.)
 * are provided by arch/arm64/lib/string.S (hand-optimised NEON assembly).
 * That code cannot run in UML (userspace process) context.
 *
 * By NOT defining __HAVE_ARCH_STRLEN etc., we fall back to the generic
 * lib/string.c implementations which do compile and export all symbols
 * needed by loadable modules.
 *
 * memcpy / memmove / memset are also redirected to generic — arm64's
 * __memcpy etc. live in arch/arm64/lib/ which is excluded from UML builds.
 */
#ifndef __UM_ASM_ARM64_STRING_H
#define __UM_ASM_ARM64_STRING_H

/*
 * Intentionally empty: do NOT define __HAVE_ARCH_STRLEN,
 * __HAVE_ARCH_STRCMP, __HAVE_ARCH_STRCHR, __HAVE_ARCH_STRNCMP,
 * __HAVE_ARCH_MEMCMP, __HAVE_ARCH_MEMCHR, __HAVE_ARCH_MEMCPY,
 * __HAVE_ARCH_MEMMOVE, __HAVE_ARCH_MEMSET.
 *
 * This lets lib/string.c provide all of them with EXPORT_SYMBOL,
 * which is required for loadable kernel modules (=m configs) to link.
 */

#endif /* __UM_ASM_ARM64_STRING_H */
