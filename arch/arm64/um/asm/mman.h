/* SPDX-License-Identifier: GPL-2.0 */
/* UML override: strip BTI/MTE/POE from arch_calc_vm_prot_bits */
#ifndef __UM_ARM64_ASM_MMAN_H
#define __UM_ARM64_ASM_MMAN_H

#include <uapi/asm/mman.h>
#include <asm-generic/mman-common.h>

/* UML does not support BTI/MTE/POE - use generic vm_prot_bits logic */

#endif
