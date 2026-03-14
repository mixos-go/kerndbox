// SPDX-License-Identifier: GPL-2.0
/* C fallback — replaced by Rust (rust/src/prctl.rs) */
#include <sys/prctl.h>
void arch_prctl_defaults(void) {
    prctl(PR_PAC_RESET_KEYS,
          (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4), 0, 0, 0);
}
