/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/setjmp.S
 *
 * kernel_setjmp / kernel_longjmp for UML on arm64.
 *
 * jmp_buf layout (struct __jmp_buf, 8 bytes each):
 *   offset  0: x19
 *   offset  8: x20
 *   offset 16: x21
 *   offset 24: x22
 *   offset 32: x23
 *   offset 40: x24
 *   offset 48: x25
 *   offset 56: x26
 *   offset 64: x27
 *   offset 72: x28
 *   offset 80: x29 (fp)
 *   offset 88: x30 (lr) — return address (JB_IP index 11)
 *   offset 96: sp        — stack pointer  (JB_SP index 12)
 *   offset 104: pad
 *   offset 112..168: d8..d15 (FP callee-saved)
 */

	.text
	.align 4
	.globl kernel_setjmp
	.type kernel_setjmp, @function
kernel_setjmp:
	/* x0 = jmp_buf pointer */
	stp	x19, x20, [x0, #0]
	stp	x21, x22, [x0, #16]
	stp	x23, x24, [x0, #32]
	stp	x25, x26, [x0, #48]
	stp	x27, x28, [x0, #64]
	stp	x29, x30, [x0, #80]	/* fp, lr */
	mov	x2,  sp
	str	x2,  [x0, #96]		/* sp */
	/* Save FP callee-saved registers d8..d15 */
	stp	d8,  d9,  [x0, #112]
	stp	d10, d11, [x0, #128]
	stp	d12, d13, [x0, #144]
	stp	d14, d15, [x0, #160]
	mov	x0, #0
	ret
	.size kernel_setjmp,.-kernel_setjmp

	.text
	.align 4
	.globl kernel_longjmp
	.type kernel_longjmp, @function
kernel_longjmp:
	/* x0 = jmp_buf pointer, x1 = return value */
	ldp	x19, x20, [x0, #0]
	ldp	x21, x22, [x0, #16]
	ldp	x23, x24, [x0, #32]
	ldp	x25, x26, [x0, #48]
	ldp	x27, x28, [x0, #64]
	ldp	x29, x30, [x0, #80]	/* fp, lr */
	ldr	x2,  [x0, #96]
	mov	sp,  x2			/* restore sp */
	/* Restore FP callee-saved registers */
	ldp	d8,  d9,  [x0, #112]
	ldp	d10, d11, [x0, #128]
	ldp	d12, d13, [x0, #144]
	ldp	d14, d15, [x0, #160]
	/* Return value: if x1==0, return 1 (longjmp(buf,0) returns 1) */
	cmp	x1, #0
	csinc	x0, x1, xzr, ne
	ret
	.size kernel_longjmp,.-kernel_longjmp
