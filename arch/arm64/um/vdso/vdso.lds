/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * arch/arm64/um/vdso/vdso.lds
 * Linker script for UML arm64 vDSO shared object.
 *
 * Every section needs an explicit :phdr tag — sections without one
 * inherit from the previous section's assignment, which causes
 * ".hash being made into a note" if .note appears first.
 *
 * Do NOT use .lds.S — cpp_lds_S injects kernel headers that confuse ld.
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

	.dynamic	: { *(.dynamic) }		:dynamic

	.note		: { *(.note.*) }		:note
	.note.linux	: { *(.note.linux) }		:note

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
