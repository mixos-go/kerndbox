// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/fault.c
 *
 * arm64 UML exception table fixup.
 *
 * When the kernel faults on a user memory access (copy_to/from_user, etc.),
 * UML's trap handler calls arch_fixup() to redirect PC to the fixup handler
 * listed in the kernel's exception table.
 *
 * arm64 exception tables use RELATIVE offsets (ARCH_HAS_RELATIVE_EXTABLE):
 *   struct exception_table_entry { int insn, fixup; short type, data; }
 *   absolute_fixup = (unsigned long)&entry->fixup + entry->fixup
 *
 * Without this: kernel panics instead of returning -EFAULT to the caller.
 * This affects ALL syscalls that touch user memory (read, write, etc.).
 */

#include <arch.h>
#include <sysdep/ptrace.h>
#include <asm/extable.h>   /* arm64 struct exception_table_entry (relative) */
#include <linux/extable.h> /* search_exception_tables() */

int arch_fixup(unsigned long address, struct uml_pt_regs *regs)
{
	const struct exception_table_entry *entry;

	entry = search_exception_tables(address);
	if (entry) {
		/*
		 * arm64 extable uses relative offsets (ARCH_HAS_RELATIVE_EXTABLE).
		 * Compute absolute fixup address:
		 *   abs = (ulong)&entry->fixup + entry->fixup
		 */
		unsigned long abs_fixup = (unsigned long)&entry->fixup +
					  (unsigned long)(long)entry->fixup;
		UPT_IP(regs) = abs_fixup;
		return 1;
	}
	return 0;
}
