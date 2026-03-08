// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/os-Linux/uaccess.c - stub for UML arm64.
 */

#include "os.h"
#include "arm64_um_os.h"

int arch_fixup(unsigned long address, struct uml_pt_regs *regs)
{
	return 0;
}
