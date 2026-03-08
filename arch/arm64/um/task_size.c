// SPDX-License-Identifier: GPL-2.0
#include <os.h>

/*
 * arch/arm64/um/task_size.c
 *
 * Provide os_get_top_address() for UML on arm64.
 * um_arch.c calls this to set task_size = host_task_size & PGDIR_MASK.
 *
 * On arm64 with 4K pages and 3-level page tables, user VA space is 39-bit
 * (512 GB). Return a value just below 512 GB so um_arch.c can compute
 * the correct TASK_SIZE.
 */

unsigned long os_get_top_address(void)
{
	/* 512 GB user VA space for arm64 with 39-bit VA (4K, 3-level) */
	return (1UL << 39);
}
