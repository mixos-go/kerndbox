// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/strrchr.c
 *
 * UML renames strrchr() to kernel_strrchr() via -Dstrrchr=kernel_strrchr
 * in KBUILD_CFLAGS (arch/um/Makefile). The rename prevents UML from
 * accidentally linking against libpthread's strrchr. We provide the
 * actual implementation here as a simple wrapper around the C library.
 */

#include <linux/export.h>
#include <linux/string.h>

#undef strrchr  /* cancel -Dstrrchr=kernel_strrchr for this file */

/* Provide kernel_strrchr — the renamed strrchr used throughout UML kernel */
char *kernel_strrchr(const char *s, int c)
{
	const char *last = NULL;

	do {
		if (*s == (char)c)
			last = s;
	} while (*s++);

	return (char *)last;
}
EXPORT_SYMBOL(kernel_strrchr);
