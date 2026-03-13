// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/fault.c
 *
 * arm64 UML exception table fixup.
 *
 * arm64 uses ARCH_HAS_RELATIVE_EXTABLE — insn and fixup are signed 32-bit
 * offsets relative to their own address (not absolute pointers like x86).
 *
 * Pattern from arch/x86/um/fault.c: define struct locally + declare
 * search_exception_tables() manually to avoid include path issues in UML.
 */
#include <arch.h>
#include <sysdep/ptrace.h>

/*
 * arm64 exception table entry — fields are relative int offsets.
 * Must match arch/arm64/include/asm/extable.h exactly.
 */
struct exception_table_entry {
	int insn;
	int fixup;
	short type;
	short data;
};

const struct exception_table_entry *search_exception_tables(unsigned long addr);

int arch_fixup(unsigned long address, struct uml_pt_regs *regs)
{
	const struct exception_table_entry *entry;

	entry = search_exception_tables(address);
	if (entry) {
		/*
		 * ARCH_HAS_RELATIVE_EXTABLE: fixup is a signed 32-bit offset
		 * relative to the address of the fixup field itself.
		 */
		unsigned long abs_fixup = (unsigned long)&entry->fixup +
					  (long)entry->fixup;
		UPT_IP(regs) = abs_fixup;
		return 1;
	}
	return 0;
}
