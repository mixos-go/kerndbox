/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * arch/arm64/um/vdso/vdso.S
 * Embeds the compiled vDSO binary into the kernel image so it can be
 * mapped into every user process at execve time.
 */

.section .data,"aw",@progbits
.balign 4096

.globl vdso_start, vdso_end
vdso_start:
.incbin "arch/arm64/um/vdso/vdso.so"
vdso_end:

.balign 4096
