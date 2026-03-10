/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * arch/arm64/um/vdso/vdso.lds.S
 * Linker script for UML arm64 vDSO shared object.
 * Adapted from arch/x86/um/vdso/vdso.lds.S
 */

#include <asm/page.h>

OUTPUT_FORMAT("elf64-littleaarch64", "elf64-littleaarch64", "elf64-littleaarch64")
OUTPUT_ARCH(aarch64)

SECTIONS {
	. = SIZEOF_HEADERS;
	.hash		: { *(.hash) }
	.gnu.hash	: { *(.gnu.hash) }
	.dynsym		: { *(.dynsym) }
	.dynstr		: { *(.dynstr) }
	.gnu.version	: { *(.gnu.version) }
	.gnu.version_d	: { *(.gnu.version_d) }
	.gnu.version_r	: { *(.gnu.version_r) }

	.note		: { *(.note.*) }		:note :text
	.eh_frame_hdr	: { *(.eh_frame_hdr) }		:text
	.eh_frame	: { KEEP (*(.eh_frame)) }	:text

	.dynamic	: { *(.dynamic) }		:text :dynamic

	.useless	: {
		*(.discard)
		*(.discard.*)
		*(.note.GNU-stack)
		*(.data .data.* .gnu.linkonce.d.*)
		*(.bss)
	}					:text

	/* vDSO code */
	.text		: { *(.text*) }			:text	= 0x90909090,2
	/* vdso-note.S */
	.note.linux	: { *(.note.linux) }		:note

	/DISCARD/	: {
		*(.got.plt)
		*(.got)
		*(.plt*)
		*(.rel*)
	}
}

PHDRS {
	text	PT_LOAD		FLAGS(5) FILEHDR PHDRS; /* PF_R|PF_X */
	dynamic	PT_DYNAMIC	FLAGS(4);		 /* PF_R */
	note	PT_NOTE		FLAGS(4);		 /* PF_R */
}

VERSION {
	LINUX_2.6 {
	global:
		clock_gettime;
		__vdso_clock_gettime;
		gettimeofday;
		__vdso_gettimeofday;
		time;
		__vdso_time;
		getcpu;
		__vdso_getcpu;
	local: *;
	};
}
