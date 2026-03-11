/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * arch/arm64/um/vdso/vdso.lds
 * Linker script for UML arm64 vDSO shared object.
 *
 * Rules:
 * - Every section must be in PT_LOAD (:text) to be "in segment"
 * - .dynamic additionally goes in PT_DYNAMIC (:dynamic)
 * - .note additionally goes in PT_NOTE (:note)
 * - Do NOT use .lds.S — cpp_lds_S injects kernel headers that break ld
 */

OUTPUT_FORMAT("elf64-littleaarch64", "elf64-littleaarch64", "elf64-littleaarch64")
OUTPUT_ARCH(aarch64)

SECTIONS {
	. = SIZEOF_HEADERS;

	.hash		: { *(.hash) }			:text
	.gnu.hash	: { *(.gnu.hash) }		:text
	.dynsym		: { *(.dynsym) }		:text
	.dynstr		: { *(.dynstr) }		:text
	.gnu.version	: { *(.gnu.version) }		:text
	.gnu.version_d	: { *(.gnu.version_d) }		:text
	.gnu.version_r	: { *(.gnu.version_r) }		:text

	.eh_frame_hdr	: { *(.eh_frame_hdr) }		:text
	.eh_frame	: { KEEP (*(.eh_frame)) }	:text

	/* Must be in :text (PT_LOAD) AND :dynamic (PT_DYNAMIC) */
	.dynamic	: { *(.dynamic) }		:text :dynamic

	/* Must be in :text (PT_LOAD) AND :note (PT_NOTE) */
	.note		: { *(.note.*) }		:text :note
	.note.linux	: { *(.note.linux) }		:text :note

	.text		: { *(.text*) }			:text

	.useless	: {
		*(.discard)
		*(.discard.*)
		*(.note.GNU-stack)
		*(.data .data.* .gnu.linkonce.d.*)
		*(.bss)
	}					:text

	/DISCARD/ : {
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
