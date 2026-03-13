// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/mem_exports.c
 *
 * Export memcpy/memset/memmove for loadable modules on UML arm64.
 *
 * patch 0016 guards user_syms.c exports under CONFIG_X86_32, so arm64
 * needs to provide these symbols itself. arch/arm64/lib/memcpy.S cannot
 * be compiled in UML context (SRCARCH=um), so we use compiler builtins.
 *
 * memcmp and memchr are already exported elsewhere in vmlinux — omitted.
 */
#include <linux/module.h>
#include <linux/string.h>

EXPORT_SYMBOL(memcpy);
EXPORT_SYMBOL(memset);
EXPORT_SYMBOL(memmove);
