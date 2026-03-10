/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * arch/arm64/um/vdso/vdso-note.S
 * ELF note for UML arm64 vDSO — marks this as a Linux vDSO object.
 * Adapted from arch/x86/um/vdso/vdso-note.S
 */
#include <linux/version.h>
#include <linux/elfnote.h>

ELFNOTE_START(Linux, 0, "a")
	.long LINUX_VERSION_CODE
ELFNOTE_END
