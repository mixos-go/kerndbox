// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/mem_exports.c
 *
 * Export memcpy/memset/memmove for loadable modules on UML arm64.
 *
 * arm64/lib/memcpy.S cannot be compiled in UML context (SRCARCH=um,
 * arm64 asm headers not in include path). Instead, we export the
 * compiler-provided builtins via EXPORT_SYMBOL so modules can link.
 *
 * Same purpose as the subarch-y = ../lib/memcpy.o pattern in x86 UML,
 * but using C builtins instead of hand-written assembly.
 */
#include <linux/module.h>
#include <linux/string.h>

/* These are provided by the compiler / generic lib/string.c.
 * We just need to EXPORT_SYMBOL them so modules can resolve the symbols. */
EXPORT_SYMBOL(memcpy);
EXPORT_SYMBOL(memset);
EXPORT_SYMBOL(memmove);
EXPORT_SYMBOL(memcmp);
EXPORT_SYMBOL(memchr);
