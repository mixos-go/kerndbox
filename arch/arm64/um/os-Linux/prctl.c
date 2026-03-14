// SPDX-License-Identifier: GPL-2.0
/* C fallback — replaced by Rust (rust/src/prctl.rs) */
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
