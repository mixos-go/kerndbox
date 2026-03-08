// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/os-Linux/prctl.c - arch_prctl_defaults for UML arm64.
 *
 * Disable PAC keys so ptrace register reads are not corrupted on
 * cores with pointer authentication enabled.
 */

#include <sys/prctl.h>
#include "arm64_um_os.h"
#include "os.h"

void arch_prctl_defaults(void)
{
	prctl(PR_PAC_RESET_KEYS,
	      PR_PAC_APIAKEY | PR_PAC_APIBKEY |
	      PR_PAC_APDAKEY | PR_PAC_APDBKEY | PR_PAC_APGAKEY,
	      0, 0, 0);
}
