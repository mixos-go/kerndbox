/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * arch/arm64/um/vdso/vdso.S
 * Embeds the compiled vDSO binary into the kernel image so it can be
 * mapped into every user process at execve time.
 */
#include <linux/init.h>

	__PAGE_ALIGNED_DATA

	.globl vdso_start, vdso_end
vdso_start:
	.incbin "arch/arm64/um/vdso/vdso.so"
vdso_end:

	.balign PAGE_SIZE
