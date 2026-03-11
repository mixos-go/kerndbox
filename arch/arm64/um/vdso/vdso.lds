/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * arch/arm64/um/vdso/vdso.lds
 *
 * NOTE: GNU ld always creates .got.plt for shared libs even with -fno-plt.
 * /DISCARD/ causes "discarded output section" error. Fix: sink everything
 * unwanted into .discard section mapped to :text — ld is happy, objcopy -S
 * removes it when producing vdso.so from vdso.so.dbg.
 */

OUTPUT_FORMAT("elf64-littleaarch64", "elf64-littleaarch64", "elf64-littleaarch64")
OUTPUT_ARCH(aarch64)

SECTIONS {
	. = SIZEOF_HEADERS;

	.hash		: { *(.hash) }			:text
	.dynsym		: { *(.dynsym) }		:text
	.dynstr		: { *(.dynstr) }		:text
	.gnu.version	: { *(.gnu.version) }		:text
	.gnu.version_d	: { *(.gnu.version_d) }		:text
	.gnu.version_r	: { *(.gnu.version_r) }		:text

	.eh_frame_hdr	: { *(.eh_frame_hdr) }		:text
	.eh_frame	: { KEEP (*(.eh_frame)) }	:text

	.dynamic	: { *(.dynamic) }		:text :dynamic

	.note		: { *(.note.*) }		:text :note
	.note.linux	: { *(.note.linux) }		:text :note

	.text		: { *(.text*) }			:text

	/* Sink — ld maps to :text so it doesn't complain, objcopy -S strips */
	.discard	: {
		*(.discard) *(.discard.*)
		*(.note.GNU-stack)
		*(.data .data.* .gnu.linkonce.d.*)
		*(.bss)
		*(.got.plt) *(.got)
		*(.plt*)
		*(.rel*) *(.rela*)
	}					:text
}

PHDRS {
	text	PT_LOAD		FLAGS(5) FILEHDR PHDRS;
	dynamic	PT_DYNAMIC	FLAGS(4);
	note	PT_NOTE		FLAGS(4);
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
