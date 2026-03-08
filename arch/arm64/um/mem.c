// SPDX-License-Identifier: GPL-2.0
/* arm64 UML: VMA name helper (no vDSO in arm64 UML) */
#include <linux/mm.h>

const char *arch_vma_name(struct vm_area_struct *vma)
{
	return NULL;
}

/* ASLR randomization bits for arm64 UML mmap layout.
 * mm/util.c:arch_mmap_rnd() reads this variable.
 * arm64 default is 18 bits (256K granularity) for 39-bit VA. */
int mmap_rnd_bits __read_mostly = 18;
#ifdef CONFIG_COMPAT
int mmap_rnd_compat_bits __read_mostly = 11;
#endif
