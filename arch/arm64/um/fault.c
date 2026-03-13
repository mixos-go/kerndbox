// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/fault.c
 *
 * arm64 UML exception table fixup.
 *
 * arm64 uses ARCH_HAS_RELATIVE_EXTABLE:
 *   struct exception_table_entry { int insn; int fixup; short type; short data; }
 * Both insn and fixup are RELATIVE offsets from their own address.
 */

#include <arch.h>
#include <sysdep/ptrace.h>
#include <linux/extable.h>

int arch_fixup(unsigned long address, struct uml_pt_regs *regs)
{
	const struct exception_table_entry *entry;

	entry = search_exception_tables(address);
	if (entry) {
		/*
		 * arm64 ARCH_HAS_RELATIVE_EXTABLE: fixup field is a
		 * signed 32-bit offset relative to &entry->fixup itself.
		 */
		unsigned long abs_fixup = (unsigned long)&entry->fixup +
					  (long)entry->fixup;
		UPT_IP(regs) = abs_fixup;
		return 1;
	}
	return 0;
}
